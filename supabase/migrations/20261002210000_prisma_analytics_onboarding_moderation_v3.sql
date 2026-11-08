-- PRISMA analytics, onboarding gate, and moderation v3.
-- One period contract: 24h / 7d / 30d / all. "detail" is rendered by callers
-- from the same selected period; aggregate charts stay compact.

alter table public.users
  add column if not exists onboarding_restricted boolean not null default false,
  add column if not exists onboarding_restriction_notified_at timestamptz;

create or replace function private.prisma_active_warning_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path=''
as $$
  select count(*)::integer
  from public.moderation_logs m
  where m.target_id=p_user_id
    and m.type='WARN'
    and m.revoked=false
    and m.status='ACTIVE'
    and (m.expires_at is null or m.expires_at>now());
$$;

revoke all on function private.prisma_active_warning_count(uuid) from public,anon,authenticated;

-- Keep denormalized warning_count synchronized when timed warnings expire.
create or replace function public.expire_punishments()
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  affected integer:=0;
  warning_rows integer:=0;
begin
  update public.moderation_logs
  set status='EXPIRED'
  where status='ACTIVE' and expires_at is not null and expires_at<=now();
  get diagnostics affected=row_count;

  update public.users
  set
    is_muted=case when muted_until is not null and muted_until<=now() then false else is_muted end,
    muted_until=case when muted_until is not null and muted_until<=now() then null else muted_until end,
    is_banned=case when banned_until is not null and banned_until<=now() then false else is_banned end,
    banned_until=case when banned_until is not null and banned_until<=now() then null else banned_until end,
    warning_count=private.prisma_active_warning_count(users.id),
    updated_at=now()
  where
    (muted_until is not null and muted_until<=now())
    or (banned_until is not null and banned_until<=now())
    or warning_count<>private.prisma_active_warning_count(users.id);

  get diagnostics warning_rows=row_count;
  return affected+warning_rows;
end;
$function$;

revoke all on function public.expire_punishments() from public,anon,authenticated;
grant execute on function public.expire_punishments() to service_role;

-- Telegram chat punishment: 1 warn = 30 days; 5 active warns = permanent ban;
-- default mute = 2 hours.
create or replace function public.bot_create_chat_punishment(
  p_chat_id bigint,
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_admin_tg_id bigint,
  p_duration integer default null
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
begin
  select id into uid from public.users
  where telegram_id=p_user_tg_id and deleted_at is null limit 1;
  select id into actor_uid from public.users
  where telegram_id=p_admin_tg_id and deleted_at is null limit 1;

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

  if typ='MUTE' and p_duration is null then
    p_duration:=120;
  end if;

  if p_duration is not null and (p_duration<=0 or p_duration>43200) then
    raise exception 'INVALID_DURATION';
  end if;

  expires:=case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') then case when p_duration is null then null else now()+make_interval(mins=>p_duration) end
    else null
  end;

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
    update public.users
    set warning_count=active_warns,updated_at=now()
    where id=uid;

    if active_warns>=5 then
      insert into public.moderation_logs(
        chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,
        duration_minutes,expires_at,source,source_type,applied_at,status,revoked
      )
      values(
        p_chat_id,uid,p_admin_tg_id,null,'BAN','Достигнуто 5 активных предупреждений',
        null,null,'BOT','AUTO_WARN_THRESHOLD',now(),'ACTIVE',false
      )
      returning id into ban_pid;

      update public.users
      set is_banned=true,banned_until=null,ban_type='PERMANENT',
          ban_reason='Достигнуто 5 активных предупреждений',
          is_whitelisted=false,updated_at=now()
      where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='MUTE' then
    update public.users
    set is_muted=true,muted_until=expires,updated_at=now()
    where id=uid;
  elsif typ='BAN' then
    update public.users
    set is_banned=true,banned_until=expires,ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now()
    where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values(
    'user',uid,'user.moderation.updated',
    jsonb_build_object('punishment_id',pid,'type',typ,'expires_at',expires,'auto_banned',auto_banned,'auto_ban_id',ban_pid)
  );

  if auto_banned then
    insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
    values(
      'user',uid,'user.moderation.updated',
      jsonb_build_object('punishment_id',ban_pid,'type','BAN','expires_at',null,'auto_ban',true)
    );
  end if;

  return json_build_object(
    'success',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),
    'auto_banned',auto_banned,'auto_ban_id',ban_pid
  );
end;
$function$;

revoke all on function public.bot_create_chat_punishment(bigint,bigint,text,text,bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_create_chat_punishment(bigint,bigint,text,text,bigint,integer) to service_role;

-- Same policy for server-wide bot punishment and automod punishment.
create or replace function public.bot_create_punishment(
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_admin_tg_id bigint,
  p_duration integer default null,
  p_source_type text default 'manual',
  p_source_id uuid default null
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
begin
  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null limit 1;
  select id into actor_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if actor_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  if uid=actor_uid then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;

  select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
  if actor_priority is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  select coalesce(r.priority,-1) into target_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=uid limit 1;
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
    source,source_type,source_id,applied_at,status
  )
  values(
    uid,p_admin_tg_id,null,typ,trim(p_reason),
    case when typ='WARN' then 43200 when typ in ('MUTE','BAN') then p_duration else null end,
    expires,'BOT',upper(coalesce(p_source_type,'MANUAL')),p_source_id,now(),'ACTIVE'
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
      update public.users set is_banned=true,banned_until=null,ban_type='PERMANENT',
        ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now() where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='MUTE' then
    update public.users set is_muted=true,muted_until=expires,updated_at=now() where id=uid;
  elsif typ='BAN' then
    update public.users set is_banned=true,banned_until=expires,
      ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
      ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now() where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires,'auto_banned',auto_banned,'auto_ban_id',ban_pid
  ));

  return json_build_object(
    'success',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),'auto_banned',auto_banned,'auto_ban_id',ban_pid
  );
end;
$function$;

revoke all on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) from public,anon,authenticated;
grant execute on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) to service_role;

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
  typ text:=upper(trim(p_type));
  active_warns integer:=0;
  auto_banned boolean:=false;
begin
  if not exists(select 1 from public.chat_settings where chat_id=p_chat_id) then
    raise exception 'AUTOMOD_CHAT_NOT_CONFIGURED';
  end if;

  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null;
  if uid is null then return json_build_object('success',true,'user_found',false); end if;

  if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_AUTOMOD_PUNISHMENT'; end if;
  if typ='MUTE' and p_duration is null then p_duration:=120; end if;
  if p_duration is not null and (p_duration<=0 or p_duration>10080) then raise exception 'INVALID_DURATION'; end if;

  expires:=case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') then case when p_duration is null then null else now()+make_interval(mins=>p_duration) end
    else null end;

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
      values(p_chat_id,uid,null,'PRISMA AUTOMOD','BAN','Достигнуто 5 активных предупреждений','BOT','AUTO_WARN_THRESHOLD',now(),'ACTIVE',false)
      returning id into ban_pid;
      update public.users set is_banned=true,banned_until=null,ban_type='PERMANENT',
        ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now() where id=uid;
      auto_banned:=true;
    end if;
  elsif typ='MUTE' then
    update public.users set is_muted=true,muted_until=expires,updated_at=now() where id=uid;
  elsif typ='BAN' then
    update public.users set is_banned=true,banned_until=expires,ban_type=case when expires is null then 'PERMANENT' else 'TEMPORARY' end,
      ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now() where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type',typ,'expires_at',expires,'auto_banned',auto_banned,'auto_ban_id',ban_pid
  ));

  return json_build_object(
    'success',true,'user_found',true,'punishment_id',pid,'expires_at',expires,
    'warning_count',private.prisma_active_warning_count(uid),'auto_banned',auto_banned,'auto_ban_id',ban_pid
  );
end;
$function$;

revoke all on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text, jsonb) to service_role;

-- Panel/server moderation: same 30d warnings, default 2h mute and 5-warn permanent ban.
create or replace function public.staff_apply_moderation(
  p_target_user_id uuid,
  p_type text,
  p_reason text,
  p_duration_minutes integer default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid:=(select auth.uid());
  target public.users%rowtype;
  actor public.users%rowtype;
  actor_priority integer;
  target_priority integer;
  typ text:=upper(trim(p_type));
  perm text;
  expires_at timestamptz;
  log_id uuid;
  auto_ban_id uuid;
  active_warns integer:=0;
  auto_banned boolean:=false;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into actor from public.users
  where auth_user_id=actor_uid and deleted_at is null limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into target from public.users
  where id=p_target_user_id and deleted_at is null for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  if typ in ('WARN','MUTE','KICK','BAN','UNMUTE','UNBAN') and target.id=actor.id then
    raise exception 'SELF_PUNISHMENT_FORBIDDEN';
  end if;

  perm:=case typ
    when 'WARN' then 'punishment.warn' when 'MUTE' then 'punishment.mute'
    when 'KICK' then 'punishment.kick' when 'BAN' then 'punishment.ban'
    when 'UNMUTE' then 'punishment.remove' when 'UNBAN' then 'punishment.remove'
    when 'WHITELIST' then 'application.approve' when 'UNWHITELIST' then 'application.reject'
    else null end;
  if perm is null then raise exception 'UNKNOWN_ACTION'; end if;
  if not private.prisma_has_user_permission(actor.id,perm) then raise exception 'PERMISSION_DENIED'; end if;

  select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor.id limit 1;
  select coalesce(r.priority,-1) into target_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target.id limit 1;
  if target_priority>=0 and actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;

  if p_reason is null or char_length(trim(p_reason)) not between 1 and 500 then raise exception 'INVALID_REASON'; end if;

  if typ='MUTE' and p_duration_minutes is null then p_duration_minutes:=120; end if;
  if p_duration_minutes is not null and (p_duration_minutes<=0 or p_duration_minutes>43200) then raise exception 'INVALID_DURATION'; end if;

  expires_at:=case
    when typ='WARN' then now()+interval '30 days'
    when typ in ('MUTE','BAN') and p_duration_minutes is not null then now()+make_interval(mins=>p_duration_minutes)
    else null
  end;

  if typ in ('WARN','MUTE','KICK','BAN') then
    insert into public.moderation_logs(
      target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
      source,applied_at,status,evidence,revoked
    )
    values(
      target.id,actor.telegram_id,
      coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
      typ,trim(p_reason),
      case when typ='WARN' then 43200 when typ in ('MUTE','BAN') then p_duration_minutes else null end,
      expires_at,'DASHBOARD',now(),'ACTIVE','{}'::jsonb,false
    )
    returning id into log_id;

    if typ='WARN' then
      active_warns:=private.prisma_active_warning_count(target.id);
      update public.users set warning_count=active_warns,updated_at=now() where id=target.id;

      if active_warns>=5 then
        insert into public.moderation_logs(
          target_id,issued_by_tg_id,issued_by_name,type,reason,source,source_type,applied_at,status,evidence,revoked
        )
        values(
          target.id,actor.telegram_id,
          coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
          'BAN','Достигнуто 5 активных предупреждений','DASHBOARD','AUTO_WARN_THRESHOLD',now(),'ACTIVE','{}'::jsonb,false
        )
        returning id into auto_ban_id;

        update public.users set
          is_banned=true,banned_until=null,ban_type='PERMANENT',
          ban_reason='Достигнуто 5 активных предупреждений',is_whitelisted=false,updated_at=now()
        where id=target.id;
        auto_banned:=true;
      end if;
    elsif typ='MUTE' then
      update public.users set is_muted=true,muted_until=expires_at,updated_at=now() where id=target.id;
    elsif typ='KICK' then
      update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
    elsif typ='BAN' then
      update public.users set
        is_banned=true,banned_until=expires_at,
        ban_type=case when expires_at is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now()
      where id=target.id;
    end if;

    insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
    values('user',target.id,'user.moderation.updated',jsonb_build_object(
      'punishment_id',log_id,'type',typ,'expires_at',expires_at,'auto_banned',auto_banned,'auto_ban_id',auto_ban_id
    ));

    if auto_banned then
      insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
      values('user',target.id,'user.moderation.updated',jsonb_build_object(
        'punishment_id',auto_ban_id,'type','BAN','expires_at',null,'auto_ban',true
      ));
    end if;
  elsif typ='UNMUTE' then
    update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id;
  elsif typ='UNBAN' then
    update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,updated_at=now() where id=target.id;
  elsif typ='WHITELIST' then
    update public.users set is_whitelisted=true,status=case when status='PENDING' then 'ACCEPTED' else status end,updated_at=now() where id=target.id;
  elsif typ='UNWHITELIST' then
    update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
  end if;

  perform private.prisma_recompute_player_rating(target.id);
  perform private.enqueue_moderation_notification(target.id,typ,trim(p_reason),p_duration_minutes);

  if auto_banned then
    perform private.enqueue_moderation_notification(target.id,'BAN','Достигнуто 5 активных предупреждений',null);
  end if;

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
  values(
    actor.id,actor.telegram_id,'moderation.'||lower(typ),'user',target.id,
    jsonb_build_object(
      'reason',trim(p_reason),'duration_minutes',p_duration_minutes,
      'moderation_log_id',log_id,'warning_count',private.prisma_active_warning_count(target.id),
      'auto_banned',auto_banned,'auto_ban_id',auto_ban_id
    )
  );

  return json_build_object(
    'success',true,'type',typ,'target_id',target.id,
    'target_telegram_id',target.telegram_id,'target_minecraft_nickname',target.minecraft_nickname,
    'moderation_log_id',log_id,'expires_at',expires_at,
    'warning_count',private.prisma_active_warning_count(target.id),'auto_banned',auto_banned,'auto_ban_id',auto_ban_id
  );
end;
$function$;

revoke all on function public.staff_apply_moderation(uuid,text,text,integer) from public,anon;
grant execute on function public.staff_apply_moderation(uuid,text,text,integer) to authenticated;

-- Onboarding: group members without an application are read/restricted by the bot.
create or replace function public.bot_list_onboarding_restriction_candidates()
returns json
language sql
security definer
set search_path=''
as $$
  select coalesce(json_agg(x order by x.tg_id),'[]'::json)
  from (
    select
      u.telegram_id as tg_id,u.telegram_username as username,u.first_name,u.last_name,u.full_name,
      u.community_is_member,u.bot_started_at,u.status,u.is_banned,u.is_muted,u.onboarding_restricted,
      u.onboarding_restriction_notified_at,
      exists(select 1 from public.applications a where a.user_id=u.id) as has_application
    from public.users u
    where u.deleted_at is null
      and u.community_is_member=true
      and u.telegram_id is not null
  ) x;
$$;

create or replace function public.bot_set_onboarding_restriction_state(
  p_tg_id bigint,
  p_restricted boolean,
  p_notified boolean default false
)
returns json
language plpgsql
security definer
set search_path=''
as $$
declare updated_count integer:=0;
begin
  update public.users u
  set onboarding_restricted=coalesce(p_restricted,false),
      onboarding_restriction_notified_at=
        case when p_notified then now()
             when not coalesce(p_restricted,false) then null
             else u.onboarding_restriction_notified_at end,
      updated_at=now()
  where u.telegram_id=p_tg_id and u.deleted_at is null;
  get diagnostics updated_count=row_count;
  if updated_count=0 then raise exception 'USER_NOT_FOUND'; end if;
  return json_build_object('success',true,'restricted',p_restricted,'notified',p_notified);
end;
$$;

revoke all on function public.bot_list_onboarding_restriction_candidates() from public,anon,authenticated;
revoke all on function public.bot_set_onboarding_restriction_state(bigint,boolean,boolean) from public,anon,authenticated;
grant execute on function public.bot_list_onboarding_restriction_candidates() to service_role;
grant execute on function public.bot_set_onboarding_restriction_state(bigint,boolean,boolean) to service_role;

-- Targeted DM broadcast for onboarding users who have actually opened the bot.
create or replace function public.staff_broadcast_onboarding(
  p_title text,
  p_body text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid:=(select auth.uid());
  actor_id uuid;
  broadcast_id uuid;
  recipients integer:=0;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'notification.send')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  if char_length(trim(coalesce(p_title,''))) not between 1 and 200 then raise exception 'INVALID_NOTIFICATION_TITLE'; end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 4000 then raise exception 'INVALID_NOTIFICATION_BODY'; end if;

  insert into public.broadcasts(created_by,title,body,target_filter,status,started_at,recipients_count)
  values(actor_id,trim(p_title),trim(p_body),
    jsonb_build_object('segment','ONBOARDING_BOT_STARTED'),
    'sending',now(),0)
  returning id into broadcast_id;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,attempts
  )
  select
    u.id,u.telegram_id,'telegram','BROADCAST',trim(p_title),trim(p_body),
    jsonb_build_object('broadcast_id',broadcast_id,'segment','ONBOARDING_BOT_STARTED'),
    'pending',0
  from public.users u
  where u.deleted_at is null
    and u.telegram_id is not null
    and u.bot_started_at is not null
    and u.community_is_member=true
    and not exists(select 1 from public.applications a where a.user_id=u.id);

  get diagnostics recipients=row_count;

  update public.broadcasts
  set recipients_count=recipients,updated_at=now()
  where id=broadcast_id;

  return json_build_object(
    'success',true,'broadcast_id',broadcast_id,'recipients',recipients,
    'unreachable_without_bot',(
      select count(*) from public.users u
      where u.deleted_at is null
        and u.community_is_member=true
        and u.bot_started_at is null
        and not exists(select 1 from public.applications a where a.user_id=u.id)
    )
  );
end;
$function$;

revoke all on function public.staff_broadcast_onboarding(text,text) from public,anon;
grant execute on function public.staff_broadcast_onboarding(text,text) to authenticated;

-- Rich staff analytics for the four common periods. Raw detail is capped to keep
-- the dashboard responsive; the exact same selected period still drives it.
drop function if exists public.staff_get_analytics(integer,integer);

create or replace function public.staff_get_analytics(
  p_days integer default 30,
  p_chat_days integer default 2,
  p_period text default '30d'
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid:=(select auth.uid());
  actor_id uuid;
  period_value text:=case lower(trim(coalesce(p_period,'30d')))
    when '24h' then '24h' when '7d' then '7d' when '30d' then '30d' when 'all' then 'all'
    else case when coalesce(p_days,30)<=1 then '24h' when coalesce(p_days,30)<=7 then '7d' else '30d' end end;
  since_at timestamptz;
  bucket_sql text;
  applications json;
  chats json;
  ratings json;
  audits json;
  admins json;
  application_trend json;
  chat_activity json;
  admin_activity json;
  top_chat_users json;
  application_status json;
  unique_chat_players integer;
  total_admin_actions integer;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'analytics.view')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  since_at:=case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null end;

  select coalesce(json_object_agg(x.status,x.count),'{}'::json)
  into application_status
  from (
    select status::text as status,count(*)::integer as count
    from public.applications
    where (since_at is null or created_at>=since_at) and not is_archived
    group by status
  ) x;

  select count(distinct user_id)::integer into unique_chat_players
  from public.chat_logs
  where since_at is null or created_at>=since_at;

  select count(*)::integer into total_admin_actions
  from public.audit_logs
  where since_at is null or created_at>=since_at;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into applications
  from (
    select id,application_no,user_id,created_at,status,nickname,platform
    from public.applications
    where (since_at is null or created_at>=since_at) and not is_archived
    order by created_at desc
    limit 5000
  ) x;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into chats
  from (
    select c.id,c.user_id,c.message,c.world,c.created_at,u.minecraft_nickname,u.telegram_username,u.full_name
    from public.chat_logs c
    join public.users u on u.id=c.user_id
    where since_at is null or c.created_at>=since_at
    order by c.created_at desc
    limit 5000
  ) x;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into audits
  from (
    select al.id,al.actor_user_id,al.actor_tg_id,al.action,al.target_type,al.target_id,al.new_data,al.created_at,
           coalesce(u.telegram_username,u.minecraft_nickname,u.full_name,al.actor_tg_id::text) as actor_name
    from public.audit_logs al
    left join public.users u on u.id=al.actor_user_id
    where (since_at is null or al.created_at>=since_at)
    order by al.created_at desc
    limit 10000
  ) x;

  select coalesce(json_agg(to_jsonb(x)),'[]'::json)
  into ratings
  from (
    select pr.value
    from public.poll_ratings pr
    join public.polls p on p.id=pr.poll_id
    where p.kind='SERVER_RATING' and (since_at is null or pr.created_at>=since_at)
  ) x;

  select coalesce(json_agg(x),'[]'::json)
  into admins
  from (
    select json_build_object(
      'telegram_id',u.telegram_id,
      'telegram_username',u.telegram_username,
      'minecraft_nickname',u.minecraft_nickname,
      'full_name',u.full_name,
      'role',r.name
    ) x
    from public.admins a
    join public.users u on u.id=a.user_id and u.deleted_at is null
    join public.roles r on r.id=a.role_id
  ) x;

  if period_value='24h' then
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into application_trend
    from (
      select date_trunc('hour',g) bucket,
             count(a.id)::integer count
      from generate_series(date_trunc('hour',now()-interval '23 hours'),date_trunc('hour',now()),interval '1 hour') g
      left join public.applications a on a.created_at>=g and a.created_at<g+interval '1 hour' and not a.is_archived
      group by g
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into chat_activity
    from (
      select date_trunc('hour',g) bucket,
             count(c.id)::integer messages,
             count(distinct c.user_id)::integer unique_players
      from generate_series(date_trunc('hour',now()-interval '23 hours'),date_trunc('hour',now()),interval '1 hour') g
      left join public.chat_logs c on c.created_at>=g and c.created_at<g+interval '1 hour'
      group by g
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into admin_activity
    from (
      select date_trunc('hour',g) bucket,
             count(al.id)::integer total_actions,
             count(distinct coalesce(al.actor_user_id::text,al.actor_tg_id::text))::integer active_admins
      from generate_series(date_trunc('hour',now()-interval '23 hours'),date_trunc('hour',now()),interval '1 hour') g
      left join public.audit_logs al on al.created_at>=g and al.created_at<g+interval '1 hour'
      group by g
    ) x;
  elsif period_value='all' then
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into application_trend
    from (
      select date_trunc('month',created_at) bucket,count(*)::integer count
      from public.applications where not is_archived
      group by 1 order by 1 desc
      limit 120
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into chat_activity
    from (
      select date_trunc('month',created_at) bucket,
             count(*)::integer messages,count(distinct user_id)::integer unique_players
      from public.chat_logs group by 1 order by 1 desc limit 120
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into admin_activity
    from (
      select date_trunc('month',created_at) bucket,
             count(*)::integer total_actions,count(distinct coalesce(actor_user_id::text,actor_tg_id::text))::integer active_admins
      from public.audit_logs group by 1 order by 1 desc limit 120
    ) x;
  else
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into application_trend
    from (
      select date_trunc('day',g) bucket,
             count(a.id)::integer count
      from generate_series(
        date_trunc('day',case when period_value='7d' then now()-interval '6 days' else now()-interval '29 days' end),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.applications a on a.created_at>=g and a.created_at<g+interval '1 day' and not a.is_archived
      group by g
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into chat_activity
    from (
      select date_trunc('day',g) bucket,
             count(c.id)::integer messages,count(distinct c.user_id)::integer unique_players
      from generate_series(
        date_trunc('day',case when period_value='7d' then now()-interval '6 days' else now()-interval '29 days' end),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.chat_logs c on c.created_at>=g and c.created_at<g+interval '1 day'
      group by g
    ) x;
    select coalesce(json_agg(x order by x.bucket),'[]'::json) into admin_activity
    from (
      select date_trunc('day',g) bucket,
             count(al.id)::integer total_actions,count(distinct coalesce(al.actor_user_id::text,al.actor_tg_id::text))::integer active_admins
      from generate_series(
        date_trunc('day',case when period_value='7d' then now()-interval '6 days' else now()-interval '29 days' end),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.audit_logs al on al.created_at>=g and al.created_at<g+interval '1 day'
      group by g
    ) x;
  end if;

  select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
  into top_chat_users
  from (
    select
      c.user_id,
      coalesce(u.minecraft_nickname,u.telegram_username,u.full_name,c.user_id::text) as player,
      count(*)::integer messages,
      max(c.created_at) last_message_at
    from public.chat_logs c
    left join public.users u on u.id=c.user_id
    where (since_at is null or c.created_at>=since_at)
    group by c.user_id,coalesce(u.minecraft_nickname,u.telegram_username,u.full_name,c.user_id::text)
    order by messages desc,last_message_at desc
    limit 15
  ) x;

  return json_build_object(
    'period',period_value,
    'from',since_at,
    'to',now(),
    'application_status',application_status,
    'unique_chat_players',coalesce(unique_chat_players,0),
    'total_admin_actions',coalesce(total_admin_actions,0),
    'applications',applications,
    'chat',chats,
    'ratings',ratings,
    'audit',audits,
    'admins',admins,
    'application_trend',application_trend,
    'chat_activity',chat_activity,
    'admin_activity',admin_activity,
    'top_chat_users',top_chat_users
  );
end;
$function$;

revoke all on function public.staff_get_analytics(integer,integer,text) from public,anon;
grant execute on function public.staff_get_analytics(integer,integer,text) to authenticated;

-- Participant analytics: same period buttons, but detailed rows are only the caller's own Minecraft chat.
drop function if exists public.participant_get_analytics();

create or replace function public.participant_get_analytics(p_period text default '30d')
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  period_value text:=case lower(trim(coalesce(p_period,'30d')))
    when '24h' then '24h' when '7d' then '7d' when '30d' then '30d' when 'all' then 'all'
    else '30d' end;
  since_at timestamptz;
  chat_activity jsonb;
  my_chat jsonb;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);

  since_at:=case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null end;

  select coalesce(jsonb_agg(x order by x.bucket),'[]'::jsonb) into chat_activity
  from (
    select date_trunc(case when period_value='24h' then 'hour' else 'day' end,g) bucket,
           count(c.id)::integer messages,
           count(distinct c.user_id)::integer unique_players
    from generate_series(
      date_trunc(case when period_value='24h' then 'hour' else 'day' end,
        coalesce(since_at, (select min(created_at) from public.chat_logs), now()-interval '30 days')),
      date_trunc(case when period_value='24h' then 'hour' else 'day' end,now()),
      case when period_value='24h' then interval '1 hour' else interval '1 day' end
    ) g
    left join public.chat_logs c on c.created_at>=g
      and c.created_at<
        g + case when period_value='24h' then interval '1 hour' else interval '1 day' end
    group by 1
    order by 1
    limit 120
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into my_chat
  from (
    select c.id,c.message,c.world,c.created_at
    from public.chat_logs c
    where c.user_id=uid and (since_at is null or c.created_at>=since_at)
    order by c.created_at desc
    limit 500
  ) x;

  return private.prisma_participant_get_analytics(uid)
    || jsonb_build_object(
      'period',period_value,'from',since_at,'to',now(),
      'chat_activity',chat_activity,'my_chat',my_chat
    );
end;
$function$;

revoke all on function public.participant_get_analytics(text) from public,anon;
grant execute on function public.participant_get_analytics(text) to authenticated;
