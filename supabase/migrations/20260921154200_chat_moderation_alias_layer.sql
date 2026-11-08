alter table public.moderation_logs add column if not exists chat_id bigint;
create index if not exists moderation_logs_chat_target_idx on public.moderation_logs(chat_id, target_id, created_at desc);

create or replace function public.bot_create_chat_punishment(p_chat_id bigint,p_user_tg_id bigint,p_type text,p_reason text,p_admin_tg_id bigint,p_duration integer default null)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; actor_uid uuid; actor_priority integer; target_priority integer; perm text; pid uuid; expires timestamptz; typ text:=upper(trim(p_type));
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
 perm:=case typ when 'WARN' then 'punishment.warn' when 'MUTE' then 'punishment.mute' when 'BAN' then 'punishment.ban' when 'KICK' then 'punishment.kick' else null end;
 if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor_uid and p.key=perm) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
 if p_duration is not null and (p_duration<=0 or p_duration>43200) then raise exception 'INVALID_DURATION'; end if;
 expires:=case when p_duration is null then null else now()+make_interval(mins=>p_duration) end;
 insert into public.moderation_logs(chat_id,target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,source,source_type,applied_at,status,revoked)
 values(p_chat_id,uid,p_admin_tg_id,null,typ,trim(p_reason),p_duration,case when typ in ('MUTE','BAN') then expires else null end,'BOT','TELEGRAM',null,'ACTIVE',false)
 returning id into pid;
 return json_build_object('success',true,'punishment_id',pid,'expires_at',expires);
end $$;