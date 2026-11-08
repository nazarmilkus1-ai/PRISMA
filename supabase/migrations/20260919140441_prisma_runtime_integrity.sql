-- PRISMA runtime integrity: canonical application, moderation, clan, activity and server workflows.
-- Safe for existing production data: only repairs constraints/functions/indexes and backfills missing history.
-- Existing users/applications are preserved.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.application_history'::regclass
      AND conname='application_history_action_check'
  ) THEN
    ALTER TABLE public.application_history DROP CONSTRAINT application_history_action_check;
  END IF;
END $$;

ALTER TABLE public.application_history
  ADD CONSTRAINT application_history_action_check
  CHECK (action = ANY (ARRAY['CREATED','APPROVED','REJECTED','REOPENED','ARCHIVED']));

CREATE OR REPLACE FUNCTION public.bot_submit_application(
  p_tg_id bigint,
  p_username text,
  p_full_name text,
  p_birth_date date,
  p_minecraft_nick text,
  p_platform text,
  p_goal text,
  p_about text
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  uid uuid;
  appid uuid;
  age_years integer;
  last_status public.application_status;
  last_cooldown timestamptz;
  v_raw_nick text;
  v_nick text;
  v_platform text;
begin
  if p_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if p_birth_date is null or p_birth_date>current_date then raise exception 'INVALID_BIRTH_DATE'; end if;

  age_years:=extract(year from age(current_date,p_birth_date))::integer;
  if age_years<14 then raise exception 'AGE_TOO_YOUNG'; end if;

  v_raw_nick:=trim(p_minecraft_nick);
  if v_raw_nick is null or v_raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;

  v_platform:=upper(trim(p_platform));
  if v_platform not in ('JAVA','BEDROCK') then raise exception 'INVALID_PLATFORM'; end if;
  v_nick:=case when v_platform='BEDROCK' then '.'||v_raw_nick else v_raw_nick end;

  select id into uid from public.users where telegram_id=p_tg_id for update;

  if uid is not null then
    select a.status, a.cooldown_until
      into last_status, last_cooldown
    from public.applications a
    where a.user_id=uid
    order by a.created_at desc, a.id desc
    limit 1;

    if last_status='PENDING' then raise exception 'APPLICATION_PENDING'; end if;
    if last_status='ACCEPTED' then raise exception 'APPLICATION_ALREADY_ACTIVE'; end if;
    if last_status='REJECTED' and last_cooldown is not null and last_cooldown>now() then
      raise exception 'APPLICATION_COOLDOWN';
    end if;
  end if;

  if exists(
    select 1
    from public.users u
    where u.telegram_id<>p_tg_id
      and lower(trim(u.minecraft_nickname))=lower(v_nick)
      and u.deleted_at is null
  ) then
    raise exception 'MINECRAFT_NICK_TAKEN';
  end if;

  if uid is null then
    insert into public.users(
      telegram_id,telegram_username,full_name,age,birth_date,minecraft_nickname,platform,
      is_whitelisted,status
    )
    values(
      p_tg_id,p_username,p_full_name,age_years,p_birth_date,v_nick,v_platform::public.platform_type,
      false,'PENDING'
    ) returning id into uid;
  else
    update public.users
      set telegram_username=p_username,
          full_name=p_full_name,
          age=age_years,
          birth_date=p_birth_date,
          minecraft_nickname=v_nick,
          platform=v_platform::public.platform_type,
          status='PENDING',
          is_whitelisted=false,
          updated_at=now()
    where id=uid;
  end if;

  insert into public.applications(
    user_id,full_name,age,nickname,platform,discovery_source,status,birth_date,goal,about,cooldown_until
  )
  values(
    uid,p_full_name,age_years,v_raw_nick,v_platform::public.platform_type,'Telegram','PENDING',
    p_birth_date,nullif(trim(p_goal),''),nullif(trim(p_about),''),null
  ) returning id into appid;

  insert into public.application_history(application_id,action,actor_tg_id)
  values(appid,'CREATED',p_tg_id);

  return json_build_object(
    'success',true,
    'user_id',uid,
    'application_id',appid,
    'minecraft_nick',v_nick
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_approve_application(
  p_application_id uuid,
  p_admin_tg_id bigint
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  aid uuid;
  uid uuid;
  perm boolean;
begin
  select a.id,a.user_id
    into aid,uid
  from public.applications a
  where a.id=p_application_id
    and a.status='PENDING'
    and not a.is_archived
  for update;

  if aid is null then raise exception 'APPLICATION_NOT_FOUND'; end if;

  select exists(
    select 1
    from public.admins a
    join public.users u on u.id=a.user_id
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where u.telegram_id=p_admin_tg_id
      and p.key='application.approve'
  ) into perm;

  if not perm then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  update public.applications
    set status='ACCEPTED',
        reviewed_by_tg_id=p_admin_tg_id,
        reviewed_at=now(),
        cooldown_until=null,
        updated_at=now()
  where id=aid;

  update public.users
    set status='ACCEPTED',
        is_whitelisted=true,
        updated_at=now()
  where id=uid;

  insert into public.application_history(application_id,action,actor_tg_id,reason)
  values(aid,'APPROVED',p_admin_tg_id,null);

  return json_build_object('success',true,'application_id',aid,'user_id',uid);
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_reject_application(
  p_application_id uuid,
  p_admin_tg_id bigint,
  p_reason text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  aid uuid;
  uid uuid;
  perm boolean;
  v_reason text;
begin
  select a.id,a.user_id
    into aid,uid
  from public.applications a
  where a.id=p_application_id
    and a.status='PENDING'
    and not a.is_archived
  for update;

  if aid is null then raise exception 'APPLICATION_NOT_FOUND'; end if;

  select exists(
    select 1
    from public.admins a
    join public.users u on u.id=a.user_id
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where u.telegram_id=p_admin_tg_id
      and p.key='application.reject'
  ) into perm;

  if not perm then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  v_reason:=left(nullif(trim(p_reason),''),2000);

  update public.applications
    set status='REJECTED',
        rejection_reason=v_reason,
        cooldown_until=now()+interval '7 days',
        reviewed_by_tg_id=p_admin_tg_id,
        reviewed_at=now(),
        updated_at=now()
  where id=aid;

  update public.users
    set status='REJECTED',
        is_whitelisted=false,
        updated_at=now()
  where id=uid;

  insert into public.application_history(application_id,action,actor_tg_id,reason)
  values(aid,'REJECTED',p_admin_tg_id,v_reason);

  return json_build_object(
    'success',true,
    'application_id',aid,
    'user_id',uid,
    'cooldown_until',now()+interval '7 days'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_lift_punishment(
  p_user_tg_id bigint,
  p_type text,
  p_admin_tg_id bigint
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  uid uuid;
  admin_uid uuid;
  pid uuid;
  new_id uuid;
  typ text:=upper(trim(p_type));
begin
  select id into uid from public.users where telegram_id=p_user_tg_id for update;
  select a.user_id into admin_uid
  from public.admins a
  join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id
  limit 1;

  if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if typ not in ('WARN','MUTE') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;

  select m.id into pid
  from public.moderation_logs m
  where m.target_id=uid
    and m.type=typ
    and m.status='ACTIVE'
    and m.revoked=false
    and (m.expires_at is null or m.expires_at>now())
  order by m.created_at desc
  limit 1;

  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  update public.moderation_logs
     set revoked=true,
         revoked_at=now(),
         revoked_by_tg_id=p_admin_tg_id,
         status='REVOKED',
         applied_at=coalesce(applied_at,now())
   where id=pid;

  if typ='MUTE' then
    update public.users
       set is_muted=false,muted_until=null,updated_at=now()
     where id=uid;
  else
    update public.users
       set warning_count=greatest(0,warning_count-1),updated_at=now()
     where id=uid;
  end if;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
  )
  values(
    uid,p_admin_tg_id,null,
    case when typ='MUTE' then 'UNMUTE' else 'UNWARN' end,
    'Покарання знято','BOT','SYSTEM_ACTION',null,false
  )
  returning id into new_id;

  return json_build_object(
    'success',true,
    'punishment_id',pid,
    'action_id',new_id,
    'type',typ
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_apply_punishment(
  p_actor_tg bigint,
  p_target_tg bigint,
  p_type text,
  p_reason text,
  p_duration_minutes integer DEFAULT NULL,
  p_evidence jsonb DEFAULT '[]'::jsonb,
  p_moderator_note text DEFAULT NULL,
  p_request_id uuid DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  actor_uid uuid;
  target_uid uuid;
  actor_priority integer;
  target_priority integer;
  expires timestamptz;
  lid uuid;
  existing_result jsonb;
  required_permission text;
begin
  if p_request_id is not null then
    select result into existing_result
    from public.idempotency_keys
    where key=p_request_id::text and operation='punishment' and expires_at>now();
    if existing_result is not null then return existing_result || jsonb_build_object('duplicate',true); end if;
  end if;

  select id into actor_uid from public.users where telegram_id=p_actor_tg limit 1;
  select id into target_uid from public.users where telegram_id=p_target_tg limit 1;

  if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if actor_uid=target_uid then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;

  select coalesce(r.priority,0) into actor_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=actor_uid limit 1;

  if actor_priority is null then raise exception 'ACTOR_NOT_ADMIN'; end if;

  select coalesce(r.priority,-1) into target_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=target_uid limit 1;

  if target_priority>=0 and actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;

  p_type:=upper(trim(p_type));
  if p_type not in ('WARN','MUTE','KICK','BAN') then raise exception 'INVALID_PUNISHMENT'; end if;
  if char_length(trim(coalesce(p_reason,'')))<3 then raise exception 'INVALID_REASON'; end if;
  if p_duration_minutes is not null and (p_duration_minutes<=0 or p_duration_minutes>43200) then raise exception 'INVALID_DURATION'; end if;

  if p_type in ('BAN','MUTE') then
    expires:=case when p_duration_minutes is null then null else now()+make_interval(mins=>p_duration_minutes) end;
  else
    expires:=null;
  end if;

  required_permission:=case
    when p_type='BAN' and p_duration_minutes is null then 'punishment.ban.permanent'
    when p_type='BAN' then 'punishment.ban.temporary'
    when p_type='MUTE' then 'punishment.mute'
    when p_type='WARN' then 'punishment.warn'
    else 'punishment.kick'
  end;

  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_uid and p.key=required_permission
  ) then raise exception 'PERMISSION_DENIED'; end if;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,type,reason,duration_minutes,expires_at,source,
    applied_at,status,evidence,moderator_note,request_id
  )
  values(
    target_uid,p_actor_tg,p_type,trim(p_reason),p_duration_minutes,expires,'DASHBOARD',
    null,'ACTIVE',coalesce(p_evidence,'[]'::jsonb),p_moderator_note,p_request_id
  )
  returning id into lid;

  update public.users set
    is_muted=case when p_type='MUTE' then true when p_type in ('BAN','KICK') then false else is_muted end,
    muted_until=case when p_type='MUTE' then expires when p_type in ('BAN','KICK') then null else muted_until end,
    is_banned=case when p_type='BAN' then true when p_type='KICK' then false else is_banned end,
    banned_until=case when p_type='BAN' then expires when p_type='KICK' then null else banned_until end,
    is_whitelisted=case when p_type in ('BAN','KICK') then false else is_whitelisted end,
    status=case when p_type in ('BAN','KICK') then 'REJECTED' else status end,
    warning_count=warning_count+case when p_type='WARN' then 1 else 0 end,
    updated_at=now()
  where id=target_uid;

  insert into public.event_audit(event_type,actor_user_id,actor_telegram_id,target_type,target_id,request_id,payload)
  values(
    'moderation.punishment',actor_uid,p_actor_tg,'user',target_uid,p_request_id,
    jsonb_build_object('type',p_type,'reason',p_reason,'duration_minutes',p_duration_minutes)
  );

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',target_uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',lid,'type',p_type,'expires_at',expires
  ));

  existing_result:=jsonb_build_object('success',true,'punishment_id',lid,'expires_at',expires,'type',p_type);

  if p_request_id is not null then
    insert into public.idempotency_keys(key,operation,actor_id,result,expires_at)
    values(p_request_id::text,'punishment',actor_uid,existing_result,now()+interval '24 hours')
    on conflict do nothing;
  end if;

  return existing_result;
end;
$function$;

CREATE TABLE IF NOT EXISTS public.activity_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source text NOT NULL,
  points integer NOT NULL DEFAULT 0 CHECK (points BETWEEN -1000 AND 1000),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.activity_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.activity_events FROM anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.activity_events TO service_role;

CREATE INDEX IF NOT EXISTS activity_events_user_created_idx
  ON public.activity_events(user_id,created_at DESC);

CREATE OR REPLACE FUNCTION public.record_activity_event(
  p_user_id uuid,
  p_source text,
  p_points integer DEFAULT 0,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare event_id uuid;
begin
  if p_user_id is null then raise exception 'USER_NOT_FOUND'; end if;
  insert into public.activity_events(user_id,source,points,metadata)
  values(p_user_id,left(trim(coalesce(p_source,'UNKNOWN')),64),coalesce(p_points,0),coalesce(p_metadata,'{}'::jsonb))
  returning id into event_id;

  update public.users
    set activity_score=greatest(0,activity_score+coalesce(p_points,0)),
        last_seen_at=now(),
        updated_at=now()
  where id=p_user_id;

  return json_build_object('success',true,'event_id',event_id);
end;
$function$;
REVOKE ALL ON FUNCTION public.record_activity_event(uuid,text,integer,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_activity_event(uuid,text,integer,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.upsert_server_heartbeat(
  p_node_id text,
  p_display_name text,
  p_version text,
  p_online_players integer,
  p_max_players integer,
  p_tps numeric DEFAULT NULL,
  p_memory_used_mb integer DEFAULT NULL,
  p_memory_max_mb integer DEFAULT NULL,
  p_uptime_seconds bigint DEFAULT NULL,
  p_world text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare now_ts timestamptz:=now();
begin
  if nullif(trim(p_node_id),'') is null then raise exception 'INVALID_NODE_ID'; end if;

  insert into public.server_nodes(
    node_id,display_name,status,version,online_players,max_players,last_heartbeat_at,metadata,updated_at
  )
  values(
    trim(p_node_id),left(coalesce(nullif(trim(p_display_name),''),trim(p_node_id)),100),'online',
    left(p_version,200),greatest(0,coalesce(p_online_players,0)),greatest(0,coalesce(p_max_players,0)),
    now_ts,coalesce(p_metadata,'{}'::jsonb),now_ts
  )
  on conflict (node_id) do update set
    display_name=excluded.display_name,
    status='online',
    version=excluded.version,
    online_players=excluded.online_players,
    max_players=excluded.max_players,
    last_heartbeat_at=now_ts,
    metadata=excluded.metadata,
    updated_at=now_ts;

  insert into public.server_metrics(
    server_name,online_players,max_players,tps,memory_used_mb,memory_max_mb,uptime_seconds,version,world,recorded_at
  )
  values(
    trim(p_node_id),greatest(0,coalesce(p_online_players,0)),greatest(0,coalesce(p_max_players,0)),
    p_tps,p_memory_used_mb,p_memory_max_mb,p_uptime_seconds,p_version,p_world,now_ts
  );

  return json_build_object(
    'success',true,
    'node_id',trim(p_node_id),
    'heartbeat_at',now_ts
  );
end;
$function$;
REVOKE ALL ON FUNCTION public.upsert_server_heartbeat(text,text,text,integer,integer,numeric,integer,integer,bigint,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_server_heartbeat(text,text,text,integer,integer,numeric,integer,integer,bigint,text,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.bot_get_server_status()
RETURNS json
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
  select json_build_object(
    'status',
      case when exists(
        select 1 from public.server_nodes
        where status='online' and last_heartbeat_at>now()-interval '90 seconds'
      ) then 'online' else 'offline' end,
    'online_nodes',
      (select count(*) from public.server_nodes
       where status='online' and last_heartbeat_at>now()-interval '90 seconds'),
    'total_nodes',(select count(*) from public.server_nodes),
    'checked_at',now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.mc_create_clan(
  p_user_id uuid,
  p_name text,
  p_tag text
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare cid uuid; tag_base text; tag_value text; suffix integer:=0;
begin
  if not exists(select 1 from public.users where id=p_user_id and status='ACCEPTED' and is_whitelisted) then
    raise exception 'USER_NOT_ALLOWED';
  end if;
  if exists(select 1 from public.clan_members where user_id=p_user_id and status='active') then
    raise exception 'USER_ALREADY_IN_CLAN';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 32 then raise exception 'INVALID_CLAN_NAME'; end if;

  tag_base:=upper(regexp_replace(trim(coalesce(p_tag,'')),'[^A-Z0-9]','','g'));
  if char_length(tag_base)<2 then
    tag_base:='C'||substr(md5(lower(trim(p_name))),1,5);
  else
    tag_base:=left(tag_base,6);
  end if;

  tag_value:=tag_base;
  while exists(select 1 from public.clans where deleted_at is null and lower(tag)=lower(tag_value)) loop
    suffix:=suffix+1;
    tag_value:=left(tag_base, greatest(1,6-char_length(suffix::text)))||suffix::text;
  end loop;

  if exists(select 1 from public.clans where deleted_at is null and lower(name)=lower(trim(p_name))) then
    raise exception 'CLAN_NAME_TAKEN';
  end if;

  insert into public.clans(name,tag,owner_id,type,status)
  values(trim(p_name),tag_value,p_user_id,'open','active')
  returning id into cid;

  insert into public.clan_members(clan_id,user_id,role,status)
  values(cid,p_user_id,'owner','active');

  update public.users set clan_id=cid,updated_at=now() where id=p_user_id;

  return json_build_object('success',true,'clan_id',cid,'tag',tag_value,'name',trim(p_name));
end;
$function$;
REVOKE ALL ON FUNCTION public.mc_create_clan(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mc_create_clan(uuid,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.mc_join_clan(
  p_user_id uuid,
  p_clan_name text
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare cid uuid; cname text; ctag text;
begin
  if not exists(select 1 from public.users where id=p_user_id and status='ACCEPTED' and is_whitelisted) then
    raise exception 'USER_NOT_ALLOWED';
  end if;
  if exists(select 1 from public.clan_members where user_id=p_user_id and status='active') then
    raise exception 'USER_ALREADY_IN_CLAN';
  end if;

  select id,name,tag into cid,cname,ctag
  from public.clans
  where deleted_at is null and status='active' and lower(name)=lower(trim(p_clan_name))
  limit 1;

  if cid is null then raise exception 'CLAN_NOT_FOUND'; end if;

  insert into public.clan_members(clan_id,user_id,role,status)
  values(cid,p_user_id,'member','active');

  update public.users set clan_id=cid,updated_at=now() where id=p_user_id;

  return json_build_object('success',true,'clan_id',cid,'tag',ctag,'name',cname);
end;
$function$;
REVOKE ALL ON FUNCTION public.mc_join_clan(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mc_join_clan(uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.mc_leave_clan(
  p_user_id uuid
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare cid uuid; owner_id uuid;
begin
  select c.id,c.owner_id into cid,owner_id
  from public.clans c
  join public.users u on u.clan_id=c.id
  where u.id=p_user_id and c.deleted_at is null
  limit 1;

  if cid is null then raise exception 'NO_CLAN'; end if;

  if owner_id=p_user_id then
    update public.users set clan_id=null,updated_at=now() where clan_id=cid;
    update public.clan_members set status='left' where clan_id=cid;
    update public.clans set deleted_at=now(),status='deleted',updated_at=now() where id=cid;
    return json_build_object('success',true,'disbanded',true,'clan_id',cid);
  end if;

  update public.clan_members set status='left' where clan_id=cid and user_id=p_user_id;
  update public.users set clan_id=null,updated_at=now() where id=p_user_id;
  return json_build_object('success',true,'disbanded',false,'clan_id',cid);
end;
$function$;
REVOKE ALL ON FUNCTION public.mc_leave_clan(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mc_leave_clan(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.register_event(
  p_user_id uuid,
  p_event_id uuid
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare e public.events%rowtype; count_now integer; already boolean;
begin
  if not exists(select 1 from public.users where id=p_user_id and status='ACCEPTED' and is_whitelisted) then
    raise exception 'USER_NOT_ALLOWED';
  end if;

  select * into e from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if e.status not in ('scheduled','live','published','registration','open','active') then
    raise exception 'EVENT_NOT_OPEN';
  end if;

  if e.registration_deadline is not null and e.registration_deadline<=now() then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  select exists(
    select 1 from public.event_participants where event_id=p_event_id and user_id=p_user_id
  ) into already;

  if already then
    return json_build_object('success',true,'duplicate',true,'event_id',p_event_id,'user_id',p_user_id);
  end if;

  if e.max_participants is not null then
    select count(*) into count_now from public.event_participants where event_id=p_event_id;
    if count_now>=e.max_participants then raise exception 'EVENT_FULL'; end if;
  end if;

  insert into public.event_participants(event_id,user_id) values(p_event_id,p_user_id);

  return json_build_object('success',true,'duplicate',false,'event_id',p_event_id,'user_id',p_user_id);
end;
$function$;
REVOKE ALL ON FUNCTION public.register_event(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_event(uuid,uuid) TO service_role;

ALTER TABLE public.server_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.server_metrics ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.server_nodes,public.server_metrics FROM anon,authenticated;

DO $$
DECLARE job_id bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='prisma-maintenance') THEN
    SELECT cron.unschedule(jobid) INTO job_id FROM cron.job WHERE jobname='prisma-maintenance' LIMIT 1;
  END IF;
  PERFORM cron.schedule(
    'prisma-maintenance',
    '*/1 * * * *',
    'select public.prisma_run_maintenance();'
  );
END $$;

INSERT INTO public.application_history(application_id,action,actor_tg_id,reason)
SELECT a.id,'APPROVED',a.reviewed_by_tg_id,'Backfilled canonical approval history'
FROM public.applications a
WHERE a.status='ACCEPTED'
  AND NOT EXISTS(
    SELECT 1 FROM public.application_history h
    WHERE h.application_id=a.id AND h.action='APPROVED'
  );
