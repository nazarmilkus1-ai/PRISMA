-- PRISMA integrity fixes.
-- Additive only; keeps existing user/application data.

-- Ensure clan creation and membership remain synchronized.
create or replace function public.bot_create_clan(p_tg_id bigint,p_name text)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; cid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if exists(select 1 from public.clan_members where user_id=uid) then raise exception 'USER_ALREADY_IN_CLAN'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 32 then raise exception 'INVALID_CLAN_NAME'; end if;
  if exists(select 1 from public.clans where lower(name)=lower(trim(p_name))) then raise exception 'CLAN_NAME_TAKEN'; end if;
  insert into public.clans(name,owner_id,type,status) values(trim(p_name),uid,'open','active') returning id into cid;
  insert into public.clan_members(clan_id,user_id,role) values(cid,uid,'owner');
  update public.users set clan_id=cid where id=uid;
  return json_build_object('success',true,'clan_id',cid,'name',trim(p_name));
end;$$;

grant execute on function public.bot_create_clan(bigint,text) to service_role;
revoke all on function public.bot_create_clan(bigint,text) from public,anon,authenticated;

-- Duration is expressed in minutes by the application layer.
create or replace function public.bot_create_punishment(p_user_tg_id bigint,p_type text,p_reason text,p_admin_tg_id bigint,p_duration integer default null,p_source_type text default 'manual',p_source_id uuid default null)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; aid uuid; perm text; pid uuid; expires timestamptz;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id;
  select a.id into aid from public.admins a join public.users u on u.id=a.user_id where u.telegram_id=p_admin_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if aid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  perm:=case lower(p_type) when 'warn' then 'punishment.warn' when 'mute' then 'punishment.mute' when 'ban' then 'punishment.ban' when 'kick' then 'punishment.kick' else null end;
  if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
  if not exists(select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id join public.admins a on a.role_id=rp.role_id where a.id=aid and p.key=perm) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
  if p_duration is not null and p_duration<=0 then raise exception 'INVALID_DURATION'; end if;
  expires:=case when p_duration is not null then now()+make_interval(mins=>p_duration) else null end;
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,source)
  values(uid,p_admin_tg_id,null,upper(p_type),trim(p_reason),p_duration,expires,'BOT') returning id into pid;
  if lower(p_type)='mute' then update public.users set is_muted=true,muted_until=expires where id=uid; end if;
  if lower(p_type)='ban' then update public.users set is_banned=true,ban_reason=trim(p_reason),is_whitelisted=false where id=uid; end if;
  return json_build_object('success',true,'punishment_id',pid,'expires_at',expires);
end;$$;

grant execute on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) to service_role;
revoke all on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) from public,anon,authenticated;
