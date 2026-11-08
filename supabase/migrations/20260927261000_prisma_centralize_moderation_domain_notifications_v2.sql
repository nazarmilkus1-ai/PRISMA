-- PRISMA v2: centralize moderation notifications and trusted punishment adapters.
-- This migration is generated from the live domain definitions to keep the
-- repository reproducible with the active Supabase contract.

CREATE OR REPLACE FUNCTION private.enqueue_moderation_notification(p_user_id uuid, p_type text, p_reason text DEFAULT NULL::text, p_duration_minutes integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  typ text:=upper(trim(coalesce(p_type,'')));
  title text;
  body text;
begin
  title:=case typ
    when 'WARN' then 'Вам вынесено предупреждение'
    when 'MUTE' then case when p_duration_minutes is null then 'Вам выдан мут' else 'Вам выдан мут на '||p_duration_minutes||' мин.' end
    when 'KICK' then 'Вас исключили с сервера'
    when 'BAN' then case when p_duration_minutes is null then 'Вы получили бан' else 'Вы получили бан на '||p_duration_minutes||' мин.' end
    when 'UNWARN' then 'Предупреждение снято'
    when 'UNMUTE' then 'Мут снят'
    when 'UNBAN' then 'Бан снят'
    when 'WHITELIST' then 'Whitelist включён'
    when 'UNWHITELIST' then 'Whitelist выключен'
    else 'Изменение модерации'
  end;

  body:=case typ
    when 'WARN' then 'Администрация вынесла вам предупреждение.'
    when 'MUTE' then 'Вы временно не можете отправлять сообщения в Minecraft.'
    when 'KICK' then 'Доступ к серверу был прекращён.'
    when 'BAN' then 'Доступ к серверу был ограничен.'
    when 'UNWARN' then 'Одно предупреждение снято администрацией.'
    when 'UNMUTE' then 'Мут снят администрацией.'
    when 'UNBAN' then 'Бан снят администрацией.'
    when 'WHITELIST' then 'Вам предоставлен whitelist.'
    when 'UNWHITELIST' then 'Whitelist для вас выключен.'
    else 'Ваш модерационный статус изменён.'
  end;

  if p_reason is not null and trim(p_reason)<>'' then
    body:=body||E'\n\nПричина: '||left(trim(p_reason),1000);
  end if;

  if p_user_id is null then return; end if;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,attempts
  )
  select
    u.id,u.telegram_id,'telegram','MODERATION',title,body,
    jsonb_build_object('moderation_type',typ,'duration_minutes',p_duration_minutes),
    'pending',0
  from public.users u
  where u.id=p_user_id
    and u.deleted_at is null
    and u.telegram_id is not null;
end;
$function$


CREATE OR REPLACE FUNCTION public.bot_create_punishment(p_user_tg_id bigint, p_type text, p_reason text, p_admin_tg_id bigint, p_duration integer DEFAULT NULL::integer, p_source_type text DEFAULT 'manual'::text, p_source_id uuid DEFAULT NULL::uuid)
 RETURNS json
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
   else null
 end;

 if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
 if not private.prisma_has_user_permission(actor_uid,perm) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

 if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
 if p_duration is not null and (p_duration<=0 or p_duration>43200) then raise exception 'INVALID_DURATION'; end if;

 expires:=case when p_duration is null then null else now()+make_interval(mins=>p_duration) end;

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
 values(
   'user',uid,'user.moderation.updated',
   jsonb_build_object('punishment_id',pid,'type',typ,'expires_at',expires)
 );

 perform private.prisma_recompute_player_rating(uid);
 perform private.enqueue_moderation_notification(uid,typ,trim(p_reason),p_duration);

 return json_build_object('success',true,'punishment_id',pid,'expires_at',expires);
end;
$function$


CREATE OR REPLACE FUNCTION public.bot_lift_punishment(p_user_tg_id bigint, p_type text, p_admin_tg_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
 if not private.prisma_has_user_permission(admin_uid,'punishment.remove') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

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
 set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,
     status='REVOKED',applied_at=coalesce(applied_at,now())
 where id=pid;

 if typ='MUTE' then
  update public.users set is_muted=false,muted_until=null,updated_at=now() where id=uid;
 else
  update public.users set warning_count=greatest(0,warning_count-1),updated_at=now() where id=uid;
 end if;

 insert into public.moderation_logs(
  target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
 )
 values(
  uid,p_admin_tg_id,null,
  case when typ='MUTE' then 'UNMUTE' else 'UNWARN' end,
  'Покарання знято','BOT','REVOKED',now(),true
 )
 returning id into new_id;

 perform private.prisma_recompute_player_rating(uid);
 perform private.enqueue_moderation_notification(
   uid,case when typ='MUTE' then 'UNMUTE' else 'UNWARN' end,'Покарання знято',null
 );

 return json_build_object(
  'success',true,'punishment_id',pid,'action_id',new_id,'type',typ
 );
end;
$function$


CREATE OR REPLACE FUNCTION public.staff_apply_moderation(p_target_user_id uuid, p_type text, p_reason text, p_duration_minutes integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_uid uuid := (select auth.uid());
  target public.users%rowtype;
  actor public.users%rowtype;
  actor_priority integer;
  target_priority integer;
  typ text := upper(trim(p_type));
  perm text;
  expires_at timestamptz;
  log_id uuid;
  accepted boolean := false;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into actor
  from public.users
  where auth_user_id=actor_uid and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into target
  from public.users
  where id=p_target_user_id and deleted_at is null
  for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  if typ in ('WARN','MUTE','KICK','BAN','UNMUTE','UNBAN') and target.id=actor.id then
    raise exception 'SELF_PUNISHMENT_FORBIDDEN';
  end if;

  perm:=case typ
    when 'WARN' then 'punishment.warn'
    when 'MUTE' then 'punishment.mute'
    when 'KICK' then 'punishment.kick'
    when 'BAN' then 'punishment.ban'
    when 'UNMUTE' then 'punishment.remove'
    when 'UNBAN' then 'punishment.remove'
    when 'WHITELIST' then 'application.approve'
    when 'UNWHITELIST' then 'application.reject'
    else null
  end;
  if perm is null then raise exception 'UNKNOWN_ACTION'; end if;

  if not private.prisma_has_user_permission(actor.id,perm) then
    raise exception 'PERMISSION_DENIED';
  end if;

  select coalesce(r.priority,0) into actor_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=actor.id
  limit 1;

  select coalesce(r.priority,-1) into target_priority
  from public.admins a join public.roles r on r.id=a.role_id
  where a.user_id=target.id
  limit 1;

  if target_priority>=0 and actor_priority<=target_priority then
    raise exception 'STAFF_HIERARCHY_FORBIDS';
  end if;

  if p_reason is null or char_length(trim(p_reason)) not between 1 and 500 then
    raise exception 'INVALID_REASON';
  end if;
  if p_duration_minutes is not null and (p_duration_minutes<=0 or p_duration_minutes>43200) then
    raise exception 'INVALID_DURATION';
  end if;

  expires_at:=case
    when typ in ('MUTE','BAN') and p_duration_minutes is not null
      then now()+make_interval(mins=>p_duration_minutes)
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
      case when typ in ('MUTE','BAN') then p_duration_minutes else null end,
      expires_at,'DASHBOARD',now(),'ACTIVE','{}'::jsonb,false
    )
    returning id into log_id;

    if typ='WARN' then
      update public.users set warning_count=coalesce(warning_count,0)+1,updated_at=now() where id=target.id;
    elsif typ='MUTE' then
      update public.users set is_muted=true,muted_until=expires_at,updated_at=now() where id=target.id;
    elsif typ='KICK' then
      update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
    elsif typ='BAN' then
      update public.users set
        is_banned=true,
        banned_until=expires_at,
        ban_type=case when expires_at is null then 'PERMANENT' else 'TEMPORARY' end,
        ban_reason=trim(p_reason),
        is_whitelisted=false,
        updated_at=now()
      where id=target.id;
    end if;

    insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
    values(
      'user',target.id,'user.moderation.updated',
      jsonb_build_object('punishment_id',log_id,'type',typ,'expires_at',expires_at)
    );

  elsif typ='UNMUTE' then
    update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id;

    insert into public.moderation_logs(
      target_id,issued_by_tg_id,issued_by_name,type,reason,source,applied_at,status,
      evidence,revoked,revoked_at,revoked_by_tg_id
    )
    values(
      target.id,actor.telegram_id,
      coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
      'UNMUTE',trim(p_reason),'DASHBOARD',now(),'REVOKED','{}'::jsonb,true,now(),actor.telegram_id
    )
    returning id into log_id;

    insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
    values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNMUTE'));

  elsif typ='UNBAN' then
    select exists(
      select 1 from public.applications a
      where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
    ) into accepted;

    update public.users
    set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,
        is_whitelisted=case when accepted then true else is_whitelisted end,
        updated_at=now()
    where id=target.id;

    insert into public.moderation_logs(
      target_id,issued_by_tg_id,issued_by_name,type,reason,source,applied_at,status,
      evidence,revoked,revoked_at,revoked_by_tg_id
    )
    values(
      target.id,actor.telegram_id,
      coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
      'UNBAN',trim(p_reason),'DASHBOARD',now(),'REVOKED','{}'::jsonb,true,now(),actor.telegram_id
    )
    returning id into log_id;

    insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
    values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNBAN'));

  elsif typ='WHITELIST' then
    update public.users
    set is_whitelisted=true,
        status=case when status='PENDING' then 'ACCEPTED' else status end,
        updated_at=now()
    where id=target.id;

  elsif typ='UNWHITELIST' then
    update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
  end if;

  perform private.prisma_recompute_player_rating(target.id);
  perform private.enqueue_moderation_notification(
    target.id,typ,trim(p_reason),p_duration_minutes
  );

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,new_data
  )
  values(
    actor.id,actor.telegram_id,'moderation.'||lower(typ),'user',target.id,
    jsonb_build_object(
      'reason',trim(p_reason),
      'duration_minutes',p_duration_minutes,
      'moderation_log_id',log_id
    )
  );

  return json_build_object(
    'success',true,'type',typ,'target_id',target.id,
    'target_telegram_id',target.telegram_id,'target_minecraft_nickname',target.minecraft_nickname,
    'moderation_log_id',log_id,'expires_at',expires_at
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.staff_manage_appeal(p_appeal_id uuid, p_action text, p_note text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 actor_uid uuid := (select auth.uid());
 actor public.users%rowtype;
 target public.users%rowtype;
 appeal public.punishment_appeals%rowtype;
 punishment public.moderation_logs%rowtype;
 action text := upper(trim(p_action));
 new_status text;
 revoke_result json;
 accepted boolean := false;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

 select * into actor
 from public.users
 where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

 if not private.prisma_has_user_permission(actor.id,'appeal.manage') then
  raise exception 'PERMISSION_DENIED';
 end if;

 if action='REVIEW' then new_status:='IN_REVIEW';
 elsif action='REJECT' then new_status:='REJECTED';
 elsif action='APPROVE' then new_status:='APPROVED';
 else raise exception 'UNKNOWN_ACTION'; end if;

 if p_note is not null and char_length(trim(p_note))>5000 then raise exception 'INVALID_NOTE'; end if;

 select * into appeal
 from public.punishment_appeals
 where id=p_appeal_id
 for update;
 if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

 select * into target
 from public.users where id=appeal.user_id for update;
 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 if action='APPROVE' and appeal.punishment_id is not null then
  select * into punishment
  from public.moderation_logs
  where id=appeal.punishment_id
  for update;

  if punishment.id is not null and not punishment.revoked
     and punishment.type in ('WARN','MUTE','BAN') then
    revoke_result:=public.staff_revoke_moderation(punishment.id,false);

  elsif punishment.id is not null and not punishment.revoked
     and punishment.type='KICK' then
    select exists(
      select 1 from public.applications a
      where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
    ) into accepted;

    update public.users
    set is_whitelisted=case when accepted and not is_banned then true else is_whitelisted end,
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
  jsonb_build_object('status',new_status,'note',p_note,'punishment_id',appeal.punishment_id)
 );

 return json_build_object(
  'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,
  'telegram_id',appeal.telegram_id,'punishment_id',appeal.punishment_id,
  'old_status',appeal.status,'status',new_status,'action',action,
  'revoke_result',revoke_result,'reviewed_by_tg_id',actor.telegram_id
 );
end;
$function$


CREATE OR REPLACE FUNCTION public.staff_revoke_moderation(p_log_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return public.staff_revoke_moderation(p_log_id,true);
end;
$function$


CREATE OR REPLACE FUNCTION public.staff_revoke_moderation(p_log_id uuid, p_notify boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_uid uuid := (select auth.uid());
  actor public.users%rowtype;
  log_row public.moderation_logs%rowtype;
  target public.users%rowtype;
  target_accepted boolean := false;
  action_type text;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into actor
  from public.users
  where auth_user_id=actor_uid and deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  select * into log_row
  from public.moderation_logs
  where id=p_log_id
  for update;
  if not found then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
  if log_row.type not in ('WARN','MUTE','BAN') then raise exception 'NOT_REVOCABLE'; end if;
  if log_row.revoked then raise exception 'ALREADY_REVOKED'; end if;

  if not private.prisma_has_user_permission(actor.id,'punishment.remove') then
    raise exception 'PERMISSION_DENIED';
  end if;

  select * into target
  from public.users
  where id=log_row.target_id
  for update;
  if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

  update public.moderation_logs
  set revoked=true,
      revoked_at=now(),
      revoked_by_tg_id=actor.telegram_id,
      revoked_by_name=coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
      status='REVOKED',
      applied_at=coalesce(applied_at,now())
  where id=p_log_id;

  if log_row.type='WARN' then
    update public.users
    set warning_count=greatest(0,warning_count-1),updated_at=now()
    where id=target.id;
    action_type:='UNWARN';
  elsif log_row.type='MUTE' then
    update public.users
    set is_muted=false,muted_until=null,updated_at=now()
    where id=target.id;
    action_type:='UNMUTE';
  else
    select exists(
      select 1
      from public.applications a
      where a.user_id=target.id
        and a.status='ACCEPTED'
        and not a.is_archived
    ) into target_accepted;

    update public.users
    set is_banned=false,
        banned_until=null,
        ban_reason=null,
        ban_type=null,
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
    target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),
    action_type,'Покарання знято','DASHBOARD','REVOKED',now(),true,now(),actor.telegram_id,
    coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),'{}'::jsonb
  );

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',target.id,'user.moderation.updated',
    jsonb_build_object('punishment_id',p_log_id,'type',action_type));

  if coalesce(p_notify,true) then
    perform private.enqueue_moderation_notification(target.id,action_type,'Покарання знято',null);
  end if;

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
  values(
    actor.id,actor.telegram_id,'moderation.revoke','user',target.id,
    jsonb_build_object('moderation_log_id',p_log_id,'type',log_row.type),
    jsonb_build_object('action_type',action_type)
  );

  return json_build_object(
    'success',true,'revoked',p_log_id,'target_id',target.id,
    'target_telegram_id',target.telegram_id,'target_minecraft_nickname',target.minecraft_nickname,
    'action_type',action_type
  );
end;
$function$



revoke all on function private.enqueue_moderation_notification(uuid,text,text,integer) from public,anon,authenticated;

revoke all on function public.staff_revoke_moderation(uuid) from public,anon;
revoke all on function public.staff_revoke_moderation(uuid,boolean) from public,anon;
revoke all on function public.staff_apply_moderation(uuid,text,text,integer) from public,anon;
revoke all on function public.staff_manage_appeal(uuid,text,text) from public,anon;
revoke all on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) from public,anon,authenticated;
revoke all on function public.bot_lift_punishment(bigint,text,bigint) from public,anon,authenticated;

grant execute on function public.staff_revoke_moderation(uuid) to authenticated;
grant execute on function public.staff_revoke_moderation(uuid,boolean) to authenticated;
grant execute on function public.staff_apply_moderation(uuid,text,text,integer) to authenticated;
grant execute on function public.staff_manage_appeal(uuid,text,text) to authenticated;
grant execute on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) to service_role;
grant execute on function public.bot_lift_punishment(bigint,text,bigint) to service_role;
