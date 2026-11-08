-- Minecraft staff moderation command gateways.
-- The service-role key remains server-only. Every mutation rechecks the actor's
-- RBAC permission and staff hierarchy in the database; plugin.yml permissions
-- are only a UI/command-registration gate, never the security boundary.

create or replace function public.mc_staff_apply_moderation(
  p_actor_user_id uuid,
  p_target_nickname text,
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
  actor public.users%rowtype;
  target public.users%rowtype;
  target_matches integer;
  actor_priority integer;
  target_priority integer;
  typ text := upper(trim(coalesce(p_type,'')));
  permission_key text;
  normalized_reason text := btrim(coalesce(p_reason,''));
  expires_at timestamptz;
  moderation_id uuid;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  select * into actor
  from public.users
  where id=p_actor_user_id and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  if p_target_nickname is null or btrim(p_target_nickname)='' or char_length(btrim(p_target_nickname))>64 then
    raise exception 'INVALID_TARGET_NICKNAME';
  end if;
  select count(*) into target_matches
  from public.users
  where deleted_at is null
    and minecraft_nickname is not null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname));
  if target_matches=0 then raise exception 'TARGET_NOT_FOUND'; end if;
  if target_matches<>1 then raise exception 'TARGET_NICKNAME_AMBIGUOUS'; end if;

  select * into target
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname))
  for update;
  if target.id is null then raise exception 'TARGET_NOT_FOUND'; end if;
  if actor.id=target.id then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;

  permission_key := case typ
    when 'WARN' then 'punishment.warn'
    when 'MUTE' then 'punishment.mute'
    when 'KICK' then 'punishment.kick'
    when 'BAN' then 'punishment.ban'
    else null
  end;
  if permission_key is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
  if not private.prisma_has_user_permission(actor.id,permission_key) then
    raise exception 'PERMISSION_DENIED';
  end if;

  select coalesce(max(r.priority),-1) into actor_priority
  from public.admins a
  join public.roles r on r.id=a.role_id
  where a.user_id=actor.id;
  if actor_priority<0 then raise exception 'PERMISSION_DENIED'; end if;

  select coalesce(max(r.priority),-1) into target_priority
  from public.admins a
  join public.roles r on r.id=a.role_id
  where a.user_id=target.id;
  if target_priority>=0 and actor_priority<=target_priority then
    raise exception 'STAFF_HIERARCHY_FORBIDS';
  end if;

  if normalized_reason='' or char_length(normalized_reason)>500 then
    raise exception 'INVALID_REASON';
  end if;
  if p_duration_minutes is not null
     and (typ not in ('MUTE','BAN') or p_duration_minutes<1 or p_duration_minutes>43200) then
    raise exception 'INVALID_DURATION';
  end if;

  expires_at := case
    when typ in ('MUTE','BAN') and p_duration_minutes is not null
      then now()+make_interval(mins=>p_duration_minutes)
    else null
  end;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,
    source,applied_at,status,evidence,revoked
  )
  values(
    target.id,actor.telegram_id,
    coalesce(actor.full_name,actor.minecraft_nickname,actor.telegram_username,actor.id::text),
    typ,normalized_reason,
    case when typ in ('MUTE','BAN') then p_duration_minutes else null end,
    expires_at,'PLUGIN',now(),'ACTIVE','{}'::jsonb,false
  )
  returning id into moderation_id;

  if typ='WARN' then
    update public.users
    set warning_count=coalesce(warning_count,0)+1,updated_at=now()
    where id=target.id;
  elsif typ='MUTE' then
    update public.users
    set is_muted=true,muted_until=expires_at,updated_at=now()
    where id=target.id;
  elsif typ='BAN' then
    update public.users
    set is_banned=true,banned_until=expires_at,
        ban_type=case when expires_at is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=normalized_reason,is_whitelisted=false,updated_at=now()
    where id=target.id;
  else
    -- KICK is a one-time disconnect; it does not revoke the whitelist.
    update public.users set updated_at=now() where id=target.id;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values(
    'user',target.id,'user.moderation.updated',
    jsonb_build_object('punishment_id',moderation_id,'type',typ,'expires_at',expires_at,'source','PLUGIN')
  );

  perform private.prisma_recompute_player_rating(target.id);
  perform private.enqueue_moderation_notification(target.id,typ,normalized_reason,p_duration_minutes);

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
  values(
    actor.id,actor.telegram_id,'moderation.'||lower(typ),'user',target.id,
    jsonb_build_object(
      'reason',normalized_reason,
      'duration_minutes',p_duration_minutes,
      'expires_at',expires_at,
      'moderation_log_id',moderation_id,
      'source','PLUGIN'
    )
  );

  return json_build_object(
    'success',true,'type',typ,'target_id',target.id,
    'target_minecraft_nickname',target.minecraft_nickname,
    'moderation_log_id',moderation_id,'expires_at',expires_at
  );
end;
$function$;

create or replace function public.mc_staff_lift_moderation(
  p_actor_user_id uuid,
  p_target_nickname text,
  p_action text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor public.users%rowtype;
  target public.users%rowtype;
  target_matches integer;
  actor_priority integer;
  target_priority integer;
  action_type text := upper(trim(coalesce(p_action,'')));
  punishment_type text;
  permission_ok boolean;
  punishment_id uuid;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  select * into actor
  from public.users
  where id=p_actor_user_id and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  if p_target_nickname is null or btrim(p_target_nickname)='' or char_length(btrim(p_target_nickname))>64 then
    raise exception 'INVALID_TARGET_NICKNAME';
  end if;
  select count(*) into target_matches
  from public.users
  where deleted_at is null
    and minecraft_nickname is not null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname));
  if target_matches=0 then raise exception 'TARGET_NOT_FOUND'; end if;
  if target_matches<>1 then raise exception 'TARGET_NICKNAME_AMBIGUOUS'; end if;

  select * into target
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname))
  for update;
  if target.id is null then raise exception 'TARGET_NOT_FOUND'; end if;
  if actor.id=target.id then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;

  if action_type='UNMUTE' then
    punishment_type := 'MUTE';
  elsif action_type='UNBAN' then
    punishment_type := 'BAN';
  else
    raise exception 'UNKNOWN_LIFT_ACTION';
  end if;

  permission_ok := private.prisma_has_user_permission(actor.id,'punishment.remove');
  if not permission_ok then raise exception 'PERMISSION_DENIED'; end if;

  select coalesce(max(r.priority),-1) into actor_priority
  from public.admins a
  join public.roles r on r.id=a.role_id
  where a.user_id=actor.id;
  if actor_priority<0 then raise exception 'PERMISSION_DENIED'; end if;

  select coalesce(max(r.priority),-1) into target_priority
  from public.admins a
  join public.roles r on r.id=a.role_id
  where a.user_id=target.id;
  if target_priority>=0 and actor_priority<=target_priority then
    raise exception 'STAFF_HIERARCHY_FORBIDS';
  end if;

  select m.id into punishment_id
  from public.moderation_logs m
  where m.target_id=target.id
    and m.type=punishment_type
    and m.status='ACTIVE'
    and not coalesce(m.revoked,false)
  order by m.created_at desc
  limit 1
  for update;
  if punishment_id is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  return private.prisma_revoke_moderation(punishment_id,actor.id,true,'PLUGIN');
end;
$function$;

create or replace function public.mc_staff_moderation_history(
  p_actor_user_id uuid,
  p_target_nickname text,
  p_limit integer default 10
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor public.users%rowtype;
  target public.users%rowtype;
  target_matches integer;
  limit_rows integer := greatest(1,least(coalesce(p_limit,10),10));
  logs_data json;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  select * into actor
  from public.users
  where id=p_actor_user_id and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if not private.prisma_has_user_permission(actor.id,'punishment.view_history') then
    raise exception 'PERMISSION_DENIED';
  end if;

  if p_target_nickname is null or btrim(p_target_nickname)='' or char_length(btrim(p_target_nickname))>64 then
    raise exception 'INVALID_TARGET_NICKNAME';
  end if;
  select count(*) into target_matches
  from public.users
  where deleted_at is null
    and minecraft_nickname is not null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname));
  if target_matches=0 then raise exception 'TARGET_NOT_FOUND'; end if;
  if target_matches<>1 then raise exception 'TARGET_NICKNAME_AMBIGUOUS'; end if;

  select * into target
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_target_nickname))
  limit 1;

  select coalesce(json_agg(row_data order by created_at desc),'[]'::json)
  into logs_data
  from (
    select
      json_build_object(
        'id',m.id,
        'type',m.type,
        'reason',m.reason,
        'duration_minutes',m.duration_minutes,
        'expires_at',m.expires_at,
        'source',m.source,
        'status',m.status,
        'revoked',coalesce(m.revoked,false),
        'issued_by_name',m.issued_by_name,
        'revoked_by_name',m.revoked_by_name,
        'created_at',m.created_at
      ) as row_data,
      m.created_at
    from public.moderation_logs m
    where m.target_id=target.id
    order by m.created_at desc
    limit limit_rows
  ) recent;

  return json_build_object(
    'success',true,
    'target',json_build_object('id',target.id,'minecraft_nickname',target.minecraft_nickname),
    'logs',logs_data
  );
end;
$function$;

revoke all on function public.mc_staff_apply_moderation(uuid,text,text,text,integer) from public,anon,authenticated;
revoke all on function public.mc_staff_lift_moderation(uuid,text,text) from public,anon,authenticated;
revoke all on function public.mc_staff_moderation_history(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.mc_staff_apply_moderation(uuid,text,text,text,integer) to service_role;
grant execute on function public.mc_staff_lift_moderation(uuid,text,text) to service_role;
grant execute on function public.mc_staff_moderation_history(uuid,text,integer) to service_role;
