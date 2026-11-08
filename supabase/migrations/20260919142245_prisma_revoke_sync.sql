-- PRISMA: staff revocations must reach Paper and remain non-active audit rows.
CREATE OR REPLACE FUNCTION public.staff_revoke_punishment(
  p_actor_tg bigint,
  p_log_id uuid,
  p_request_id uuid DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  actor_uid uuid;
  log_row public.moderation_logs%rowtype;
  target_uid uuid;
  required text;
  action_type text;
  action_id uuid;
  target_is_accepted boolean;
begin
  select u.id into actor_uid
  from public.users u
  where u.telegram_id=p_actor_tg
  limit 1;
  if actor_uid is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into log_row
  from public.moderation_logs
  where id=p_log_id
  for update;
  if not found then raise exception 'PUNISHMENT_NOT_FOUND'; end if;

  select required_permission into required
  from (values
    ('WARN','punishment.remove'),
    ('MUTE','punishment.remove'),
    ('BAN','punishment.remove')
  ) v(kind,required_permission)
  where kind=log_row.type;

  if required is null then raise exception 'NOT_REVOCABLE'; end if;

  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_uid and p.key=required
  ) then raise exception 'PERMISSION_DENIED'; end if;

  target_uid:=log_row.target_id;

  update public.moderation_logs
     set revoked=true,
         revoked_at=now(),
         revoked_by_tg_id=p_actor_tg,
         status='REVOKED',
         applied_at=coalesce(applied_at,now())
   where id=p_log_id;

  if log_row.type='MUTE' then
    update public.users
       set is_muted=false,muted_until=null,updated_at=now()
     where id=target_uid;
    action_type:='UNMUTE';
  elsif log_row.type='BAN' then
    select exists(
      select 1 from public.applications a
      where a.user_id=target_uid
        and a.status='ACCEPTED'
        and not a.is_archived
    ) into target_is_accepted;

    update public.users
       set is_banned=false,
           banned_until=null,
           is_whitelisted=case when target_is_accepted then true else is_whitelisted end,
           status=case when target_is_accepted then 'ACCEPTED' else status end,
           updated_at=now()
     where id=target_uid;
    action_type:='UNBAN';
  elsif log_row.type='WARN' then
    update public.users
       set warning_count=greatest(0,warning_count-1),updated_at=now()
     where id=target_uid;
    action_type:='UNWARN';
  else
    raise exception 'NOT_REVOCABLE';
  end if;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked,revoked_at,revoked_by_tg_id
  )
  values(
    target_uid,p_actor_tg,null,action_type,'Покарання знято',
    'DASHBOARD','REVOKED',null,true,now(),p_actor_tg
  )
  returning id into action_id;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values(
    'user',target_uid,'user.moderation.updated',
    jsonb_build_object(
      'punishment_id',p_log_id,
      'action_id',action_id,
      'type',action_type
    )
  );

  insert into public.event_audit(
    event_type,actor_user_id,actor_telegram_id,target_type,target_id,request_id,payload
  )
  values(
    'moderation.revoke',actor_uid,p_actor_tg,'user',target_uid,p_request_id,
    jsonb_build_object('punishment_id',p_log_id,'type',log_row.type,'action_type',action_type)
  );

  return json_build_object(
    'success',true,
    'revoked',p_log_id,
    'action_id',action_id,
    'action_type',action_type
  );
end;
$function$;
