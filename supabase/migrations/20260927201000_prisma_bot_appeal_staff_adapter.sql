-- PRISMA v2: trusted Telegram staff appeal read/decision adapters.
-- Business state is mutated atomically inside these service-role-only functions.

create or replace function public.bot_list_appeals(
  p_admin_tg_id bigint,
  p_status text default 'OPEN',
  p_limit integer default 50
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  filter_status text := upper(trim(coalesce(p_status,'OPEN')));
  lim integer := greatest(1,least(coalesce(p_limit,50),200));
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if not public.bot_check_admin_permission(p_admin_tg_id,'appeal.view') then raise exception 'PERMISSION_DENIED'; end if;
  if filter_status not in ('ALL','OPEN','IN_REVIEW','APPROVED','REJECTED') then raise exception 'INVALID_STATUS'; end if;

  return coalesce((
    select json_agg(x order by (x->>'created_at')::timestamptz asc)
    from (
      select json_build_object(
        'id',pa.id,'telegram_id',pa.telegram_id,'punishment_id',pa.punishment_id,
        'reason',pa.reason,'status',pa.status,'reviewed_by_tg_id',pa.reviewed_by_tg_id,
        'review_note',pa.review_note,'created_at',pa.created_at,'updated_at',pa.updated_at
      ) x
      from public.punishment_appeals pa
      where filter_status='ALL' or pa.status=filter_status
      order by pa.created_at asc
      limit lim
    ) rows_data
  ),'[]'::json);
end;
$function$;

revoke all on function public.bot_list_appeals(bigint,text,integer) from public,anon,authenticated;
grant execute on function public.bot_list_appeals(bigint,text,integer) to service_role;

create or replace function public.bot_manage_appeal(
  p_appeal_id uuid,
  p_action text,
  p_admin_tg_id bigint,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  admin_uid uuid;
  target public.users%rowtype;
  appeal public.punishment_appeals%rowtype;
  punishment public.moderation_logs%rowtype;
  action text := upper(trim(p_action));
  new_status text;
  accepted boolean := false;
  punishment_action_id uuid;
  was_lifted boolean := false;
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;

  select a.user_id into admin_uid
  from public.admins a
  join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id and u.deleted_at is null
  limit 1;
  if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  if not public.bot_check_admin_permission(p_admin_tg_id,'appeal.manage') then
    raise exception 'PERMISSION_DENIED';
  end if;

  if action='REVIEW' then new_status:='IN_REVIEW';
  elsif action='REJECT' then new_status:='REJECTED';
  elsif action='APPROVE' then new_status:='APPROVED';
  else raise exception 'UNKNOWN_ACTION'; end if;

  if p_note is not null and char_length(trim(p_note))>5000 then
    raise exception 'INVALID_NOTE';
  end if;

  select * into appeal
  from public.punishment_appeals
  where id=p_appeal_id
  for update;
  if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
  if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

  select * into target
  from public.users
  where id=appeal.user_id
  for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  if action='APPROVE' and appeal.punishment_id is not null then
    select * into punishment
    from public.moderation_logs
    where id=appeal.punishment_id
    for update;

    if punishment.id is not null and not punishment.revoked then
      if punishment.type='WARN' then
        update public.users set warning_count=greatest(0,warning_count-1),updated_at=now() where id=target.id;
        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED',
            applied_at=coalesce(applied_at,now())
        where id=punishment.id;
        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        ) values(target.id,p_admin_tg_id,null,'UNWARN','Покарання знято апеляцією','BOT','REVOKED',now(),true)
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='MUTE' then
        update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id;
        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED',
            applied_at=coalesce(applied_at,now())
        where id=punishment.id;
        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        ) values(target.id,p_admin_tg_id,null,'UNMUTE','Покарання знято апеляцією','BOT','REVOKED',now(),true)
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='BAN' then
        select exists(
          select 1 from public.applications a
          where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
        ) into accepted;
        update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,
          is_whitelisted=case when accepted then true else is_whitelisted end,updated_at=now()
        where id=target.id;
        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED',
            applied_at=coalesce(applied_at,now())
        where id=punishment.id;
        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        ) values(target.id,p_admin_tg_id,null,'UNBAN','Покарання знято апеляцією','BOT','REVOKED',now(),true)
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='KICK' then
        select exists(
          select 1 from public.applications a
          where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
        ) into accepted;
        update public.users set
          is_whitelisted=case when accepted and not is_banned then true else is_whitelisted end,
          updated_at=now()
        where id=target.id;
        insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
        values('user',target.id,'user.moderation.updated',
          jsonb_build_object('type','UNREGISTER_KICK','appeal_id',appeal.id));
        was_lifted:=true;
      end if;
    end if;
  end if;

  perform private.prisma_recompute_player_rating(target.id);

  update public.punishment_appeals
  set status=new_status,reviewed_by_tg_id=p_admin_tg_id,
      review_note=case when p_note is null then review_note else trim(p_note) end,updated_at=now()
  where id=appeal.id;

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
  values(
    admin_uid,p_admin_tg_id,'appeal.'||lower(action),'punishment_appeal',appeal.id,
    jsonb_build_object('status',appeal.status),
    jsonb_build_object('status',new_status,'note',p_note,'punishment_id',appeal.punishment_id,
      'was_lifted',was_lifted,'punishment_action_id',punishment_action_id)
  );

  return json_build_object(
    'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,'telegram_id',appeal.telegram_id,
    'punishment_id',appeal.punishment_id,'old_status',appeal.status,'status',new_status,
    'action',action,'was_lifted',was_lifted,'punishment_action_id',punishment_action_id
  );
end;
$function$;

revoke all on function public.bot_manage_appeal(uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_manage_appeal(uuid,text,bigint,text) to service_role;
