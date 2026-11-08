-- PRISMA v2: canonical private moderation revoke primitive.
-- Bot and panel appeal approvals must not depend on auth.uid().

create or replace function private.prisma_revoke_moderation(
  p_log_id uuid,
  p_actor_user_id uuid,
  p_notify boolean default true,
  p_source public.moderation_source default 'DASHBOARD'
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor public.users%rowtype;
  log_row public.moderation_logs%rowtype;
  target public.users%rowtype;
  target_accepted boolean := false;
  action_type text;
  new_id uuid;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into actor
  from public.users
  where id=p_actor_user_id and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  if not private.prisma_has_user_permission(actor.id,'punishment.remove') then
    raise exception 'PERMISSION_DENIED';
  end if;

  select * into log_row
  from public.moderation_logs
  where id=p_log_id
  for update;
  if not found then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
  if log_row.type not in ('WARN','MUTE','BAN') then raise exception 'NOT_REVOCABLE'; end if;
  if log_row.revoked then raise exception 'ALREADY_REVOKED'; end if;

  select * into target
  from public.users
  where id=log_row.target_id
  for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),
      revoked_by_tg_id=actor.telegram_id,
      revoked_by_name=coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
      status='REVOKED',
      applied_at=coalesce(applied_at,now())
  where id=p_log_id;

  if log_row.type='WARN' then
    update public.users set warning_count=greatest(0,warning_count-1),updated_at=now() where id=target.id;
    action_type:='UNWARN';
  elsif log_row.type='MUTE' then
    update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id;
    action_type:='UNMUTE';
  else
    select exists(
      select 1 from public.applications a
      where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
    ) into target_accepted;

    update public.users
    set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,
        is_whitelisted=case when target_accepted then true else is_whitelisted end,
        updated_at=now()
    where id=target.id;
    action_type:='UNBAN';
  end if;

  perform private.prisma_recompute_player_rating(target.id);

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,
    revoked,revoked_at,revoked_by_tg_id,revoked_by_name,evidence
  )
  values(
    target.id,actor.telegram_id,
    coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
    action_type,'Покарання знято',p_source,'REVOKED',now(),true,now(),
    actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
    '{}'::jsonb
  )
  returning id into new_id;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',target.id,'user.moderation.updated',
    jsonb_build_object('punishment_id',p_log_id,'type',action_type));

  if coalesce(p_notify,true) then
    perform private.enqueue_moderation_notification(target.id,action_type,'Покарання знято',null);
  end if;

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  values(
    actor.id,actor.telegram_id,'moderation.revoke','user',target.id,
    jsonb_build_object('moderation_log_id',p_log_id,'type',log_row.type),
    jsonb_build_object('action_type',action_type,'source',p_source::text,'moderation_action_id',new_id)
  );

  return json_build_object(
    'success',true,'revoked',p_log_id,'target_id',target.id,
    'target_telegram_id',target.telegram_id,'target_minecraft_nickname',target.minecraft_nickname,
    'action_type',action_type,'moderation_action_id',new_id
  );
end;
$function$;

revoke all on function private.prisma_revoke_moderation(uuid,uuid,boolean,public.moderation_source)
from public,anon,authenticated;

drop function if exists public.staff_revoke_moderation(uuid);
drop function if exists public.staff_revoke_moderation(uuid,boolean);

create function public.staff_revoke_moderation(p_log_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare actor_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u
  where u.auth_user_id=auth.uid() and u.deleted_at is null limit 1;
  if actor_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  return private.prisma_revoke_moderation(p_log_id,actor_id,true,'DASHBOARD');
end;
$function$;

revoke all on function public.staff_revoke_moderation(uuid) from public,anon;
grant execute on function public.staff_revoke_moderation(uuid) to authenticated;

create function public.staff_revoke_moderation(p_log_id uuid,p_notify boolean)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare actor_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u
  where u.auth_user_id=auth.uid() and u.deleted_at is null limit 1;
  if actor_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  return private.prisma_revoke_moderation(p_log_id,actor_id,p_notify,'DASHBOARD');
end;
$function$;

revoke all on function public.staff_revoke_moderation(uuid,boolean) from public,anon;
grant execute on function public.staff_revoke_moderation(uuid,boolean) to authenticated;

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
  revoke_result json;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  select * into actor from public.users where id=p_actor_user_id and deleted_at is null limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if not private.prisma_has_user_permission(actor.id,'appeal.manage') then raise exception 'PERMISSION_DENIED'; end if;

  if action='REVIEW' then new_status:='IN_REVIEW';
  elsif action='REJECT' then new_status:='REJECTED';
  elsif action='APPROVE' then new_status:='APPROVED';
  else raise exception 'UNKNOWN_ACTION'; end if;

  if p_note is not null and char_length(trim(p_note))>5000 then raise exception 'INVALID_NOTE'; end if;

  select * into appeal from public.punishment_appeals where id=p_appeal_id for update;
  if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
  if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

  select * into target from public.users where id=appeal.user_id and deleted_at is null for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  if action='APPROVE' and appeal.punishment_id is not null then
    select * into punishment from public.moderation_logs where id=appeal.punishment_id for update;

    if punishment.id is not null and not punishment.revoked
       and punishment.status='ACTIVE'
       and punishment.type in ('WARN','MUTE','BAN') then
      revoke_result:=private.prisma_revoke_moderation(
        punishment.id,actor.id,false,p_source
      );
    elsif punishment.id is not null and not punishment.revoked
       and punishment.status='ACTIVE'
       and punishment.type='KICK' then

      if not private.prisma_has_user_permission(actor.id,'punishment.remove') then
        raise exception 'PERMISSION_DENIED';
      end if;

      update public.users
      set is_whitelisted=case when exists(
        select 1 from public.applications a
        where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
      ) and not is_banned then true else is_whitelisted end,
      updated_at=now()
      where id=target.id;

      insert into public.sync_outbox(
        aggregate_type,aggregate_id,event_type,payload
      )
      values(
        'user',target.id,'user.moderation.updated',
        jsonb_build_object('type','UNREGISTER_KICK','appeal_id',appeal.id)
      );
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
    actor.id,actor.telegram_id,'appeal.'||lower(action),'punishment_appeal',appeal.id,
    jsonb_build_object('status',appeal.status),
    jsonb_build_object(
      'status',new_status,'note',p_note,'punishment_id',appeal.punishment_id,
      'revoke_result',revoke_result,'source',p_source::text
    )
  );

  return json_build_object(
    'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,
    'telegram_id',appeal.telegram_id,'punishment_id',appeal.punishment_id,
    'old_status',appeal.status,'status',new_status,'action',action,
    'revoke_result',revoke_result
  );
end;
$function$;

revoke all on function private.prisma_manage_appeal(uuid,uuid,text,text,public.moderation_source)
from public,anon,authenticated;
