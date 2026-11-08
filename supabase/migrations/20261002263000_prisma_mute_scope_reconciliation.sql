-- Reconcile overlapping PRISMA mutes instead of letting one new/lifted mute
-- overwrite the expiry/state of other active punishments.

create or replace function private.prisma_recompute_user_mute_state(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  has_indefinite boolean := false;
  latest_expiry timestamptz;
  effective_until timestamptz;
  muted boolean := false;
begin
  if p_user_id is null then raise exception 'USER_ID_REQUIRED'; end if;

  select
    coalesce(bool_or(m.expires_at is null), false),
    max(m.expires_at) filter (where m.expires_at is not null and m.expires_at > now())
  into has_indefinite, latest_expiry
  from public.moderation_logs m
  where m.target_id=p_user_id
    and m.type='MUTE'
    and m.status='ACTIVE'
    and not m.revoked
    and (m.expires_at is null or m.expires_at > now());

  muted := has_indefinite or latest_expiry is not null;
  effective_until := case when muted and not has_indefinite then latest_expiry else null end;

  update public.users
  set is_muted=muted, muted_until=effective_until, updated_at=now()
  where id=p_user_id and deleted_at is null;

  return jsonb_build_object(
    'is_muted',muted,
    'muted_until',effective_until,
    'has_indefinite_mute',has_indefinite
  );
end;
$function$;

create or replace function private.prisma_effective_chat_mute_state(p_user_id uuid,p_chat_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  has_indefinite boolean := false;
  latest_expiry timestamptz;
  effective_until timestamptz;
  muted boolean := false;
begin
  if p_user_id is null or p_chat_id is null then
    return jsonb_build_object(
      'chat_is_muted',false,
      'chat_muted_until',null,
      'chat_has_indefinite_mute',false
    );
  end if;

  select
    coalesce(bool_or(m.expires_at is null), false),
    max(m.expires_at) filter (where m.expires_at is not null and m.expires_at > now())
  into has_indefinite, latest_expiry
  from public.moderation_logs m
  where m.target_id=p_user_id
    and m.type='MUTE'
    and m.status='ACTIVE'
    and not m.revoked
    and (m.expires_at is null or m.expires_at > now())
    and (m.chat_id is null or m.chat_id=p_chat_id);

  muted := has_indefinite or latest_expiry is not null;
  effective_until := case when muted and not has_indefinite then latest_expiry else null end;

  return jsonb_build_object(
    'chat_is_muted',muted,
    'chat_muted_until',effective_until,
    'chat_has_indefinite_mute',has_indefinite
  );
end;
$function$;

revoke all on function private.prisma_recompute_user_mute_state(uuid) from public,anon,authenticated;
revoke all on function private.prisma_effective_chat_mute_state(uuid,bigint) from public,anon,authenticated;

create or replace function public.bot_apply_automod_punishment(
  p_chat_id bigint,
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_duration integer default null,
  p_rule_key text default 'automod',
  p_payload jsonb default '{}'::jsonb
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  pid uuid;
  ban_pid uuid;
  expires timestamptz;
  typ text := upper(trim(p_type));
  active_warns integer := 0;
  auto_banned boolean := false;
  global_mute jsonb;
  chat_mute jsonb;
begin
  if not exists(select 1 from public.chat_settings where chat_id=p_chat_id) then
    raise exception 'AUTOMOD_CHAT_NOT_CONFIGURED';
  end if;

  select id into uid from public.users
  where telegram_id=p_user_tg_id and deleted_at is null;
  if uid is null then return json_build_object('success',true,'user_found',false); end if;

  if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_AUTOMOD_PUNISHMENT'; end if;
  if typ='MUTE' and p_duration is null then p_duration:=120; end if;
  if p_duration is not null and (p_duration<=0 or p_duration>10080) then raise exception 'INVALID_DURATION'; end if;

  expires := case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') then case when p_duration is null then null else now()+make_interval(mins=>p_duration) end
    else null
  end;

  insert into public.moderation_logs(
    chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,source_type,evidence,applied_at,status,revoked
  )
  values(
    p_chat_id,uid,null,'PRISMA AUTOMOD',typ,trim(p_reason),
    case when typ='WARN' then 43200 when typ in ('MUTE','BAN') then p_duration else null end,
    expires,'BOT','AUTOMOD',
    jsonb_build_array(jsonb_build_object('chat_id',p_chat_id,'rule_key',p_rule_key,'payload',coalesce(p_payload,'{}'::jsonb))),
    now(),'ACTIVE',false
  )
  returning id into pid;

  if typ='WARN' then
    active_warns:=private.prisma_active_warning_count(uid);
    update public.users set warning_count=active_warns,updated_at=now() where id=uid;
    if active_warns>=5 then
      insert into public.moderation_logs(
        chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,source,source_type,applied_at,status,revoked
      )
      values(
        p_chat_id,uid,null,'PRISMA AUTOMOD','BAN',
        'Достигнуто 5 активных предупреждений','BOT','AUTO_WARN_THRESHOLD',now(),'ACTIVE',false
      )
      returning id into ban_pid;

      update public.users
      set is_banned=true,banned_until=null,ban_type='PERMANENT',
          ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now()
      where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='BAN' then
    update public.users
    set is_banned=true,banned_until=expires,
        ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now()
    where id=uid;
  end if;

  global_mute:=private.prisma_recompute_user_mute_state(uid);
  chat_mute:=private.prisma_effective_chat_mute_state(uid,p_chat_id);

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires,
    'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until'
  ));

  return json_build_object(
    'success',true,'user_found',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),
    'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until',
    'has_indefinite_mute',coalesce((global_mute->>'has_indefinite_mute')::boolean,false),
    'chat_is_muted',coalesce((chat_mute->>'chat_is_muted')::boolean,false),
    'chat_muted_until',chat_mute->'chat_muted_until',
    'chat_has_indefinite_mute',coalesce((chat_mute->>'chat_has_indefinite_mute')::boolean,false)
  );
end;
$function$;

create or replace function public.bot_create_chat_punishment(
  p_chat_id bigint,p_user_tg_id bigint,p_type text,p_reason text,p_admin_tg_id bigint,p_duration integer default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  actor_uid uuid;
  actor_priority integer;
  target_priority integer;
  perm text;
  pid uuid;
  ban_pid uuid;
  expires timestamptz;
  typ text:=upper(trim(p_type));
  active_warns integer:=0;
  auto_banned boolean:=false;
  global_mute jsonb;
  chat_mute jsonb;
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
  if target_priority>=0 and actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;

  perm:=case typ
    when 'WARN' then 'punishment.warn'
    when 'MUTE' then 'punishment.mute'
    when 'BAN' then 'punishment.ban'
    when 'KICK' then 'punishment.kick'
    else null end;
  if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
  if not exists(
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_uid and p.key=perm
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
  if typ='MUTE' and p_duration is null then p_duration:=120; end if;
  if p_duration is not null and (p_duration<=0 or p_duration>43200) then raise exception 'INVALID_DURATION'; end if;

  expires:=case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') then case when p_duration is null then null else now()+make_interval(mins=>p_duration) end
    else null end;

  insert into public.moderation_logs(
    chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,source_type,applied_at,status,revoked
  )
  values(
    p_chat_id,uid,p_admin_tg_id,null,typ,trim(p_reason),
    case when typ='WARN' then 43200 when typ in ('MUTE','BAN') then p_duration else null end,
    case when typ in ('WARN','MUTE','BAN') then expires else null end,
    'BOT','TELEGRAM',now(),'ACTIVE',false
  )
  returning id into pid;

  if typ='WARN' then
    active_warns:=private.prisma_active_warning_count(uid);
    update public.users set warning_count=active_warns,updated_at=now() where id=uid;
    if active_warns>=5 then
      insert into public.moderation_logs(
        chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
        source,source_type,applied_at,status,revoked
      )
      values(
        p_chat_id,uid,p_admin_tg_id,null,'BAN','Достигнуто 5 активных предупреждений',
        null,null,'BOT','AUTO_WARN_THRESHOLD',now(),'ACTIVE',false
      )
      returning id into ban_pid;

      update public.users
      set is_banned=true,banned_until=null,ban_type='PERMANENT',
          ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now()
      where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='BAN' then
    update public.users
    set is_banned=true,banned_until=expires,
        ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now()
    where id=uid;
  end if;

  global_mute:=private.prisma_recompute_user_mute_state(uid);
  chat_mute:=private.prisma_effective_chat_mute_state(uid,p_chat_id);

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires,
    'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until'
  ));

  return json_build_object(
    'success',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),
    'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until',
    'has_indefinite_mute',coalesce((global_mute->>'has_indefinite_mute')::boolean,false),
    'chat_is_muted',coalesce((chat_mute->>'chat_is_muted')::boolean,false),
    'chat_muted_until',chat_mute->'chat_muted_until',
    'chat_has_indefinite_mute',coalesce((chat_mute->>'chat_has_indefinite_mute')::boolean,false)
  );
end;
$function$;

create or replace function public.bot_lift_chat_punishment(
  p_chat_id bigint,p_user_tg_id bigint,p_type text,p_admin_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  admin_uid uuid;
  pid uuid;
  typ text:=upper(trim(p_type));
  warning_count_now integer:=0;
  global_mute jsonb;
  chat_mute jsonb;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null limit 1;
  select id into admin_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;

  if not exists(
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=admin_uid and p.key='punishment.remove'
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  select m.id into pid
  from public.moderation_logs m
  where m.chat_id=p_chat_id and m.target_id=uid and m.type=typ
    and m.status='ACTIVE' and m.revoked=false
    and (m.expires_at is null or m.expires_at>now())
  order by m.created_at desc limit 1;

  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED'
  where id=pid;

  if typ='WARN' then
    warning_count_now:=private.prisma_active_warning_count(uid);
    update public.users set warning_count=warning_count_now,updated_at=now() where id=uid;
  elsif typ='MUTE' then
    global_mute:=private.prisma_recompute_user_mute_state(uid);
    chat_mute:=private.prisma_effective_chat_mute_state(uid,p_chat_id);
  elsif typ='BAN' then
    update public.users
    set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,updated_at=now()
    where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type','UN'||typ,
    'warning_count',private.prisma_active_warning_count(uid),
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end
  ));

  return json_build_object(
    'success',true,'punishment_id',pid,'type',typ,
    'warning_count',private.prisma_active_warning_count(uid),
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end,
    'has_indefinite_mute',case when typ='MUTE' then global_mute->'has_indefinite_mute' else null end,
    'chat_is_muted',case when typ='MUTE' then chat_mute->'chat_is_muted' else null end,
    'chat_muted_until',case when typ='MUTE' then chat_mute->'chat_muted_until' else null end,
    'chat_has_indefinite_mute',case when typ='MUTE' then chat_mute->'chat_has_indefinite_mute' else null end
  );
end;
$function$;

create or replace function public.bot_create_punishment(
  p_user_tg_id bigint,p_type text,p_reason text,p_admin_tg_id bigint,
  p_duration integer default null,p_source_type text default 'manual',p_source_id uuid default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  actor_uid uuid;
  actor_priority integer;
  target_priority integer;
  perm text;
  pid uuid;
  ban_pid uuid;
  expires timestamptz;
  typ text:=upper(trim(p_type));
  active_warns integer:=0;
  auto_banned boolean:=false;
  global_mute jsonb;
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
  if target_priority>=0 and actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;

  perm:=case typ
    when 'WARN' then 'punishment.warn' when 'MUTE' then 'punishment.mute'
    when 'BAN' then 'punishment.ban' when 'KICK' then 'punishment.kick' else null end;
  if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
  if not private.prisma_has_user_permission(actor_uid,perm) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
  if typ='MUTE' and p_duration is null then p_duration:=120; end if;
  if p_duration is not null and (p_duration<=0 or p_duration>43200) then raise exception 'INVALID_DURATION'; end if;

  expires:=case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') then case when p_duration is null then null else now()+make_interval(mins=>p_duration) end
    else null end;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,source_type,source_id,applied_at,status,revoked
  )
  values(
    uid,p_admin_tg_id,null,typ,trim(p_reason),
    case when typ='WARN' then 43200 when typ in ('MUTE','BAN') then p_duration else null end,
    expires,'BOT',upper(coalesce(p_source_type,'MANUAL')),p_source_id,now(),'ACTIVE',false
  )
  returning id into pid;

  if typ='WARN' then
    active_warns:=private.prisma_active_warning_count(uid);
    update public.users set warning_count=active_warns,updated_at=now() where id=uid;
    if active_warns>=5 then
      insert into public.moderation_logs(
        target_id,issued_by_tg_id,issued_by_name,type,reason,source,source_type,applied_at,status,revoked
      )
      values(uid,p_admin_tg_id,null,'BAN','Достигнуто 5 активных предупреждений','BOT','AUTO_WARN_THRESHOLD',now(),'ACTIVE',false)
      returning id into ban_pid;

      update public.users
      set is_banned=true,banned_until=null,ban_type='PERMANENT',
          ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now()
      where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='BAN' then
    update public.users
    set is_banned=true,banned_until=expires,
        ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now()
    where id=uid;
  end if;

  global_mute:=private.prisma_recompute_user_mute_state(uid);

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires,'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until'
  ));

  return json_build_object(
    'success',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),
    'auto_banned',auto_banned,'auto_ban_id',ban_pid,
    'is_muted',coalesce((global_mute->>'is_muted')::boolean,false),
    'muted_until',global_mute->'muted_until',
    'has_indefinite_mute',coalesce((global_mute->>'has_indefinite_mute')::boolean,false)
  );
end;
$function$;

create or replace function public.bot_lift_punishment(
  p_user_tg_id bigint,p_type text,p_admin_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  admin_uid uuid;
  pid uuid;
  new_id uuid;
  typ text:=upper(trim(p_type));
  accepted boolean:=false;
  action_type text;
  global_mute jsonb;
begin
  select id into uid
  from public.users where telegram_id=p_user_tg_id and deleted_at is null
  for update;

  select a.user_id into admin_uid
  from public.admins a join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id and u.deleted_at is null limit 1;

  if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;
  if not private.prisma_has_user_permission(admin_uid,'punishment.remove') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  select m.id into pid
  from public.moderation_logs m
  where m.target_id=uid and m.type=typ and m.status='ACTIVE'
    and not m.revoked and (m.expires_at is null or m.expires_at>now())
  order by m.created_at desc limit 1 for update;
  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,
      status='REVOKED',applied_at=coalesce(applied_at,now())
  where id=pid;

  if typ='MUTE' then
    global_mute:=private.prisma_recompute_user_mute_state(uid);
    action_type:='UNMUTE';
  elsif typ='WARN' then
    update public.users set warning_count=private.prisma_active_warning_count(uid),updated_at=now()
    where id=uid;
    action_type:='UNWARN';
  else
    select exists(
      select 1 from public.applications a
      where a.user_id=uid and a.status='ACCEPTED' and not a.is_archived
    ) into accepted;

    update public.users
    set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,
        is_whitelisted=case when accepted then true else is_whitelisted end,
        updated_at=now()
    where id=uid;
    action_type:='UNBAN';
  end if;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
  )
  values(uid,p_admin_tg_id,null,action_type,'Покарання знято','BOT','REVOKED',now(),true)
  returning id into new_id;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',action_type,
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end
  ));

  perform private.prisma_recompute_player_rating(uid);
  perform private.enqueue_moderation_notification(uid,action_type,'Покарання знято',null);

  return json_build_object(
    'success',true,'punishment_id',pid,'action_id',new_id,'type',typ,'action_type',action_type,
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end,
    'has_indefinite_mute',case when typ='MUTE' then global_mute->'has_indefinite_mute' else null end
  );
end;
$function$;

create or replace function public.bot_revoke_chat_punishment(p_punishment_id uuid,p_admin_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  admin_uid uuid;
  target_uid uuid;
  typ text;
  chat_id_value bigint;
  global_mute jsonb;
  chat_mute jsonb;
begin
  select id into admin_uid from public.users
  where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  if not exists(
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=admin_uid and p.key='punishment.remove'
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  select m.target_id,m.type,m.chat_id into target_uid,typ,chat_id_value
  from public.moderation_logs m
  where m.id=p_punishment_id and m.chat_id is not null and m.status='ACTIVE' and not m.revoked
  limit 1;
  if target_uid is null then raise exception 'PUNISHMENT_NOT_FOUND'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED'
  where id=p_punishment_id;

  if typ='MUTE' then
    global_mute:=private.prisma_recompute_user_mute_state(target_uid);
    chat_mute:=private.prisma_effective_chat_mute_state(target_uid,chat_id_value);
  elsif typ='WARN' then
    update public.users set warning_count=private.prisma_active_warning_count(target_uid),updated_at=now()
    where id=target_uid;
  elsif typ='BAN' then
    update public.users
    set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,updated_at=now()
    where id=target_uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',target_uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',p_punishment_id,'type','UN'||typ,
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end
  ));

  return json_build_object(
    'success',true,'punishment_id',p_punishment_id,'type',typ,
    'is_muted',case when typ='MUTE' then global_mute->'is_muted' else null end,
    'muted_until',case when typ='MUTE' then global_mute->'muted_until' else null end,
    'has_indefinite_mute',case when typ='MUTE' then global_mute->'has_indefinite_mute' else null end,
    'chat_is_muted',case when typ='MUTE' then chat_mute->'chat_is_muted' else null end,
    'chat_muted_until',case when typ='MUTE' then chat_mute->'chat_muted_until' else null end,
    'chat_has_indefinite_mute',case when typ='MUTE' then chat_mute->'chat_has_indefinite_mute' else null end
  );
end;
$function$;

revoke all on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text,jsonb) to service_role;

revoke all on function public.bot_create_chat_punishment(bigint,bigint,text,text,bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_create_chat_punishment(bigint,bigint,text,text,bigint,integer) to service_role;

revoke all on function public.bot_lift_chat_punishment(bigint,bigint,text,bigint) from public,anon,authenticated;
grant execute on function public.bot_lift_chat_punishment(bigint,bigint,text,bigint) to service_role;

revoke all on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) from public,anon,authenticated;
grant execute on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) to service_role;

revoke all on function public.bot_lift_punishment(bigint,text,bigint) from public,anon,authenticated;
grant execute on function public.bot_lift_punishment(bigint,text,bigint) to service_role;

revoke all on function public.bot_revoke_chat_punishment(uuid,bigint) from public,anon,authenticated;
grant execute on function public.bot_revoke_chat_punishment(uuid,bigint) to service_role;
