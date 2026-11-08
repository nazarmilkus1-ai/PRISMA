-- Make Telegram moderation actions first-class pending sync events for Paper.
CREATE OR REPLACE FUNCTION public.bot_create_punishment(
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_admin_tg_id bigint,
  p_duration integer DEFAULT NULL,
  p_source_type text DEFAULT 'manual',
  p_source_id uuid DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  uid uuid;
  actor_uid uuid;
  actor_priority integer;
  target_priority integer;
  perm text;
  pid uuid;
  expires timestamptz;
  typ text:=upper(trim(p_type));
begin
  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null limit 1;
  select id into actor_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if actor_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  if uid=actor_uid then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;

  select coalesce(r.priority,0) into actor_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=actor_uid limit 1;
  if actor_priority is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  select coalesce(r.priority,-1) into target_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=uid limit 1;
  if target_priority>=0 and actor_priority<=target_priority then
    raise exception 'STAFF_HIERARCHY_FORBIDS';
  end if;

  perm:=case typ
    when 'WARN' then 'punishment.warn'
    when 'MUTE' then 'punishment.mute'
    when 'BAN' then 'punishment.ban'
    when 'KICK' then 'punishment.kick'
    else null end;
  if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;

  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_uid and p.key=perm
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then
    raise exception 'INVALID_REASON';
  end if;
  if p_duration is not null and (p_duration<=0 or p_duration>43200) then
    raise exception 'INVALID_DURATION';
  end if;

  expires:=case
    when p_duration is null then null
    else now()+make_interval(mins=>p_duration)
  end;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,source_type,source_id,applied_at,status
  )
  values(
    uid,p_admin_tg_id,null,typ,trim(p_reason),p_duration,
    case when typ in ('MUTE','BAN') then expires else null end,
    'BOT',upper(coalesce(p_source_type,'MANUAL')),p_source_id,null,'ACTIVE'
  )
  returning id into pid;

  if typ='WARN' then
    update public.users set warning_count=coalesce(warning_count,0)+1,updated_at=now() where id=uid;
  elsif typ='MUTE' then
    update public.users set is_muted=true,muted_until=expires,updated_at=now() where id=uid;
  elsif typ='BAN' then
    update public.users set is_banned=true,banned_until=expires,ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now() where id=uid;
  elsif typ='KICK' then
    update public.users set updated_at=now() where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires
  ));

  return json_build_object('success',true,'punishment_id',pid,'expires_at',expires);
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_apply_automod_punishment(
  p_chat_id bigint,
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_duration integer DEFAULT NULL,
  p_rule_key text DEFAULT 'automod',
  p_payload jsonb DEFAULT '{}'::jsonb
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  uid uuid;
  pid uuid;
  expires timestamptz;
begin
  if not exists(select 1 from public.chat_settings cs where cs.chat_id=p_chat_id) then
    raise exception 'AUTOMOD_CHAT_NOT_CONFIGURED';
  end if;

  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null;
  if uid is null then return json_build_object('success',true,'user_found',false); end if;

  if lower(p_type) not in ('warn','mute','ban') then raise exception 'UNSUPPORTED_AUTOMOD_PUNISHMENT'; end if;
  if p_duration is not null and (p_duration<=0 or p_duration>10080) then raise exception 'INVALID_DURATION'; end if;

  expires:=case when p_duration is not null then now()+make_interval(mins=>p_duration) else null end;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,source_type,evidence,applied_at,status
  )
  values(
    uid,null,'PRISMA AUTOMOD',upper(p_type),trim(p_reason),p_duration,expires,
    'BOT','AUTOMOD',jsonb_build_array(jsonb_build_object(
      'chat_id',p_chat_id,'rule_key',p_rule_key,'payload',coalesce(p_payload,'{}'::jsonb)
    )),null,'ACTIVE'
  )
  returning id into pid;

  if lower(p_type)='warn' then
    update public.users set warning_count=coalesce(warning_count,0)+1,updated_at=now() where id=uid;
  elsif lower(p_type)='mute' then
    update public.users set is_muted=true,muted_until=expires,updated_at=now() where id=uid;
  elsif lower(p_type)='ban' then
    update public.users set is_banned=true,banned_until=expires,ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now() where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',upper(p_type),'expires_at',expires
  ));

  return json_build_object('success',true,'user_found',true,'punishment_id',pid,'expires_at',expires);
end;
$function$;
