-- Canonical staff moderation mutations. Panel calls these with the authenticated Supabase session.
create or replace function public.staff_apply_moderation(p_target_user_id uuid,p_type text,p_reason text,p_duration_minutes integer default null)
returns json language plpgsql security definer set search_path='' as $$
declare
 actor_uid uuid := (select auth.uid()); target public.users%rowtype; actor public.users%rowtype;
 actor_priority integer; target_priority integer; typ text := upper(trim(p_type)); perm text;
 expires_at timestamptz; log_id uuid; accepted boolean := false;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 select * into target from public.users where id=p_target_user_id and deleted_at is null for update;
 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;
 if typ in ('WARN','MUTE','KICK','BAN','UNMUTE','UNBAN') and target.id=actor.id then raise exception 'SELF_PUNISHMENT_FORBIDDEN'; end if;
 perm:=case typ when 'WARN' then 'punishment.warn' when 'MUTE' then 'punishment.mute' when 'KICK' then 'punishment.kick' when 'BAN' then 'punishment.ban' when 'UNMUTE' then 'punishment.remove' when 'UNBAN' then 'punishment.remove' when 'WHITELIST' then 'application.approve' when 'UNWHITELIST' then 'application.reject' else null end;
 if perm is null then raise exception 'UNKNOWN_ACTION'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor.id and p.key=perm) then raise exception 'PERMISSION_DENIED'; end if;
 select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor.id limit 1;
 select coalesce(r.priority,-1) into target_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target.id limit 1;
 if target_priority>=0 and actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 if p_reason is null or char_length(trim(p_reason)) not between 1 and 500 then raise exception 'INVALID_REASON'; end if;
 if p_duration_minutes is not null and (p_duration_minutes<=0 or p_duration_minutes>43200) then raise exception 'INVALID_DURATION'; end if;
 expires_at:=case when typ in ('MUTE','BAN') and p_duration_minutes is not null then now()+make_interval(mins=>p_duration_minutes) else null end;

 if typ in ('WARN','MUTE','KICK','BAN') then
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,source,applied_at,status,evidence,revoked)
  values(target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),typ,trim(p_reason),case when typ in ('MUTE','BAN') then p_duration_minutes else null end,expires_at,'DASHBOARD',now(),'ACTIVE','{}'::jsonb,false) returning id into log_id;
  if typ='WARN' then update public.users set warning_count=coalesce(warning_count,0)+1,updated_at=now() where id=target.id;
  elsif typ='MUTE' then update public.users set is_muted=true,muted_until=expires_at,updated_at=now() where id=target.id;
  elsif typ='KICK' then update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
  elsif typ='BAN' then update public.users set is_banned=true,banned_until=expires_at,ban_type=case when expires_at is null then 'PERMANENT' else 'TEMPORARY' end,ban_reason=trim(p_reason),is_whitelisted=false,updated_at=now() where id=target.id;
  end if;
  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload) values('user',target.id,'user.moderation.updated',jsonb_build_object('punishment_id',log_id,'type',typ,'expires_at',expires_at));
 elsif typ='UNMUTE' then
  update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id;
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,source,applied_at,status,evidence,revoked,revoked_at,revoked_by_tg_id)
  values(target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),'UNMUTE',trim(p_reason),'DASHBOARD',now(),'REVOKED','{}'::jsonb,true,now(),actor.telegram_id) returning id into log_id;
  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload) values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNMUTE'));
 elsif typ='UNBAN' then
  select exists(select 1 from public.applications a where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived) into accepted;
  update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,is_whitelisted=case when accepted then true else is_whitelisted end,updated_at=now() where id=target.id;
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,source,applied_at,status,evidence,revoked,revoked_at,revoked_by_tg_id)
  values(target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),'UNBAN',trim(p_reason),'DASHBOARD',now(),'REVOKED','{}'::jsonb,true,now(),actor.telegram_id) returning id into log_id;
  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload) values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNBAN'));
 elsif typ='WHITELIST' then
  update public.users set is_whitelisted=true,status=case when status='PENDING' then 'ACCEPTED' else status end,updated_at=now() where id=target.id;
 elsif typ='UNWHITELIST' then
  update public.users set is_whitelisted=false,updated_at=now() where id=target.id;
 end if;

 insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
 values(actor.id,actor.telegram_id,'moderation.'||lower(typ),'user',target.id,jsonb_build_object('reason',trim(p_reason),'duration_minutes',p_duration_minutes,'moderation_log_id',log_id));
 return json_build_object('success',true,'type',typ,'target_id',target.id,'moderation_log_id',log_id,'expires_at',expires_at);
end;
$$;

revoke execute on function public.staff_apply_moderation(uuid,text,text,integer) from public,anon;
grant execute on function public.staff_apply_moderation(uuid,text,text,integer) to authenticated;

create or replace function public.staff_revoke_moderation(p_log_id uuid)
returns json language plpgsql security definer set search_path='' as $$
declare
 actor_uid uuid := (select auth.uid()); actor public.users%rowtype; log_row public.moderation_logs%rowtype;
 target public.users%rowtype; target_accepted boolean := false; action_type text;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 select * into log_row from public.moderation_logs where id=p_log_id for update;
 if not found then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
 if log_row.type not in ('WARN','MUTE','BAN') then raise exception 'NOT_REVOCABLE'; end if;
 if log_row.revoked then raise exception 'ALREADY_REVOKED'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor.id and p.key='punishment.remove') then raise exception 'PERMISSION_DENIED'; end if;
 select * into target from public.users where id=log_row.target_id for update;
 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 update public.moderation_logs set revoked=true,revoked_at=now(),revoked_by_tg_id=actor.telegram_id,revoked_by_name=coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),status='REVOKED',applied_at=coalesce(applied_at,now()) where id=p_log_id;
 if log_row.type='WARN' then
  update public.users set warning_count=greatest(0,warning_count-1),updated_at=now() where id=target.id; action_type:='UNWARN';
 elsif log_row.type='MUTE' then
  update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target.id; action_type:='UNMUTE';
 else
  select exists(select 1 from public.applications a where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived) into target_accepted;
  update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,is_whitelisted=case when target_accepted then true else is_whitelisted end,updated_at=now() where id=target.id; action_type:='UNBAN';
 end if;

 insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked,revoked_at,revoked_by_tg_id,revoked_by_name,evidence)
 values(target.id,actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),action_type,'Покарання знято','DASHBOARD','REVOKED',now(),true,now(),actor.telegram_id,coalesce(actor.full_name,actor.telegram_username,actor.telegram_id::text),'{}'::jsonb);
 insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload) values('user',target.id,'user.moderation.updated',jsonb_build_object('punishment_id',p_log_id,'type',action_type));
 insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
 values(actor.id,actor.telegram_id,'moderation.revoke','user',target.id,jsonb_build_object('moderation_log_id',p_log_id,'type',log_row.type),jsonb_build_object('action_type',action_type));
 return json_build_object('success',true,'revoked',p_log_id,'target_id',target.id,'action_type',action_type);
end;
$$;

revoke execute on function public.staff_revoke_moderation(uuid) from public,anon;
grant execute on function public.staff_revoke_moderation(uuid) to authenticated;