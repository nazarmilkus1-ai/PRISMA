-- PRISMA v2: canonical appeal mutation domain.
-- Bot and panel adapters resolve identity only; all business state changes
-- happen in one private function.

create or replace function private.prisma_manage_appeal(
  p_appeal_id uuid,
  p_actor_user_id uuid,
  p_action text,
  p_note text default null,
  p_source public.moderation_source default 'DASHBOARD'
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor public.users%rowtype;
  target public.users%rowtype;
  appeal public.punishment_appeals%rowtype;
  punishment public.moderation_logs%rowtype;
  action text:=upper(trim(p_action));
  new_status text;
  accepted boolean:=false;
  was_lifted boolean:=false;
  punishment_action_id uuid;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into actor
  from public.users
  where id=p_actor_user_id and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  if not private.prisma_has_user_permission(actor.id,'appeal.manage') then
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
  if appeal.status not in ('OPEN','IN_REVIEW') then
    raise exception 'APPEAL_ALREADY_CLOSED';
  end if;

  select * into target
  from public.users
  where id=appeal.user_id and deleted_at is null
  for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  if action='APPROVE' and appeal.punishment_id is not null then
    select * into punishment
    from public.moderation_logs
    where id=appeal.punishment_id
    for update;

    if punishment.id is not null and not punishment.revoked and punishment.status='ACTIVE' then
      if punishment.type='WARN' then
        update public.users
        set warning_count=greatest(0,warning_count-1),updated_at=now()
        where id=target.id;

        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=actor.telegram_id,
            revoked_by_name=coalesce(actor.full_name,actor.telegram_username),
            status='REVOKED',applied_at=coalesce(applied_at,now())
        where id=punishment.id;

        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        )
        values(
          target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username),
          'UNWARN','Покарання знято апеляцією',p_source,'REVOKED',now(),true
        )
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='MUTE' then
        update public.users
        set is_muted=false,muted_until=null,updated_at=now()
        where id=target.id;

        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=actor.telegram_id,
            revoked_by_name=coalesce(actor.full_name,actor.telegram_username),
            status='REVOKED',applied_at=coalesce(applied_at,now())
        where id=punishment.id;

        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        )
        values(
          target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username),
          'UNMUTE','Покарання знято апеляцією',p_source,'REVOKED',now(),true
        )
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='BAN' then
        select exists(
          select 1 from public.applications a
          where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
        ) into accepted;

        update public.users
        set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,
            is_whitelisted=case when accepted then true else is_whitelisted end,
            updated_at=now()
        where id=target.id;

        update public.moderation_logs
        set revoked=true,revoked_at=now(),revoked_by_tg_id=actor.telegram_id,
            revoked_by_name=coalesce(actor.full_name,actor.telegram_username),
            status='REVOKED',applied_at=coalesce(applied_at,now())
        where id=punishment.id;

        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
        )
        values(
          target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username),
          'UNBAN','Покарання знято апеляцією',p_source,'REVOKED',now(),true
        )
        returning id into punishment_action_id;
        was_lifted:=true;

      elsif punishment.type='KICK' then
        select exists(
          select 1 from public.applications a
          where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
        ) into accepted;

        update public.users
        set is_whitelisted=case when accepted and not is_banned then true else is_whitelisted end,
            updated_at=now()
        where id=target.id;

        insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
        values(
          'user',target.id,'user.moderation.updated',
          jsonb_build_object('type','UNREGISTER_KICK','appeal_id',appeal.id)
        );
        was_lifted:=true;
      end if;
    end if;
  end if;

  perform private.prisma_recompute_player_rating(target.id);

  update public.punishment_appeals
  set status=new_status,
      reviewed_by_tg_id=actor.telegram_id,
      review_note=case when p_note is null then review_note else trim(p_note) end,
      updated_at=now()
  where id=appeal.id;

  perform private.enqueue_appeal_status_notification(
    appeal.id,appeal.user_id,new_status,p_note
  );

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  values(
    actor.id,actor.telegram_id,'appeal.'||lower(action),
    'punishment_appeal',appeal.id,
    jsonb_build_object('status',appeal.status),
    jsonb_build_object(
      'status',new_status,'note',p_note,
      'punishment_id',appeal.punishment_id,
      'was_lifted',was_lifted,
      'punishment_action_id',punishment_action_id,
      'source',p_source::text
    )
  );

  return json_build_object(
    'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,
    'telegram_id',appeal.telegram_id,'punishment_id',appeal.punishment_id,
    'old_status',appeal.status,'status',new_status,'action',action,
    'was_lifted',was_lifted,'punishment_action_id',punishment_action_id
  );
end;
$function$;

revoke all on function private.prisma_manage_appeal(uuid,uuid,text,text,public.moderation_source)
from public,anon,authenticated;

drop function if exists public.staff_manage_appeal(uuid,text,text);

create function public.staff_manage_appeal(
  p_appeal_id uuid,
  p_action text,
  p_note text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare actor_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=auth.uid()
    and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;

  return private.prisma_manage_appeal(
    p_appeal_id,actor_id,p_action,p_note,'DASHBOARD'
  );
end;
$function$;

revoke all on function public.staff_manage_appeal(uuid,text,text)
from public,anon;
grant execute on function public.staff_manage_appeal(uuid,text,text)
to authenticated;

drop function if exists public.bot_manage_appeal(uuid,text,bigint,text);

create function public.bot_manage_appeal(
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
declare actor_id uuid;
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;

  select a.user_id into actor_id
  from public.admins a
  join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id
    and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  return private.prisma_manage_appeal(
    p_appeal_id,actor_id,p_action,p_note,'BOT'
  );
end;
$function$;

revoke all on function public.bot_manage_appeal(uuid,text,bigint,text)
from public,anon,authenticated;
grant execute on function public.bot_manage_appeal(uuid,text,bigint,text)
to service_role;
