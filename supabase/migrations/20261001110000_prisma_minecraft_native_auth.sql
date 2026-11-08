-- PRISMA 2.0.0: native Minecraft Java authentication.
-- SimpleLogin is intentionally removed from the runtime contract.
-- Password hashes use pgcrypto bcrypt and are never exposed to browser/client roles.
-- Java login is verified by the Paper plugin through server-only RPC.
-- Participant-site password changes are scoped by auth.uid().
-- Telegram exposes status only; password input stays on the web UI.

create table if not exists public.minecraft_auth_credentials (
  user_id uuid primary key references public.users(id) on delete cascade,
  password_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0 and failed_attempts <= 5),
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz
);

alter table public.minecraft_auth_credentials enable row level security;
revoke all on table public.minecraft_auth_credentials from public, anon, authenticated;
grant all on table public.minecraft_auth_credentials to service_role;

create index if not exists minecraft_auth_credentials_locked_idx
  on public.minecraft_auth_credentials(locked_until)
  where locked_until is not null;

create or replace function public.mc_auth_status(
  p_nickname text,
  p_minecraft_uuid uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_platform text;
  v_bound_uuid uuid;
  v_configured boolean;
  v_locked_until timestamptz;
begin
  select u.id,u.platform,u.minecraft_uuid
    into v_user_id,v_platform,v_bound_uuid
  from public.users u
  where u.deleted_at is null
    and u.status='ACCEPTED'
    and u.is_whitelisted=true
    and u.is_banned=false
    and lower(trim(coalesce(u.minecraft_nickname,'')))=lower(trim(p_nickname))
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('error','USER_NOT_FOUND');
  end if;

  if upper(coalesce(v_platform,'')) <> 'JAVA' then
    return jsonb_build_object('error','PLATFORM_NOT_JAVA');
  end if;

  if v_bound_uuid is not null and v_bound_uuid <> p_minecraft_uuid then
    return jsonb_build_object('error','IDENTITY_MISMATCH');
  end if;

  select exists(
      select 1 from public.minecraft_auth_credentials c where c.user_id=v_user_id
    )
    into v_configured;

  select c.locked_until
    into v_locked_until
  from public.minecraft_auth_credentials c
  where c.user_id=v_user_id;

  return jsonb_build_object(
    'ok',true,
    'configured',coalesce(v_configured,false),
    'locked_until',v_locked_until
  );
end;
$function$;

create or replace function public.mc_auth_set_password(
  p_user_id uuid,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_platform text;
  v_nickname text;
  v_existing boolean;
begin
  if p_new_password is null or octet_length(p_new_password) < 8 or octet_length(p_new_password) > 72
     or char_length(trim(p_new_password)) < 8 then
    return jsonb_build_object('error','INVALID_PASSWORD');
  end if;

  select upper(coalesce(u.platform::text,'')),u.minecraft_nickname
    into v_platform,v_nickname
  from public.users u
  where u.id=p_user_id and u.deleted_at is null
    and u.status='ACCEPTED'
    and u.is_whitelisted=true
    and u.is_banned=false;

  if v_platform is null then
    return jsonb_build_object('error','USER_NOT_FOUND');
  end if;
  if v_platform <> 'JAVA' then
    return jsonb_build_object('error','PLATFORM_NOT_JAVA');
  end if;
  if v_nickname is null or trim(v_nickname)='' then
    return jsonb_build_object('error','MINECRAFT_NICK_MISSING');
  end if;

  select exists(select 1 from public.minecraft_auth_credentials c where c.user_id=p_user_id)
    into v_existing;
  if v_existing then
    return jsonb_build_object('error','AUTH_ALREADY_CONFIGURED');
  end if;

  insert into public.minecraft_auth_credentials(user_id,password_hash)
  values(p_user_id,extensions.crypt(p_new_password,extensions.gen_salt('bf',12)));

  return jsonb_build_object('ok',true,'configured',true);
end;
$function$;

create or replace function public.mc_auth_change_password(
  p_user_id uuid,
  p_current_password text,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hash text;
begin
  if p_new_password is null or octet_length(p_new_password) < 8 or octet_length(p_new_password) > 72
     or char_length(trim(p_new_password)) < 8 then
    return jsonb_build_object('error','INVALID_PASSWORD');
  end if;

  select c.password_hash
    into v_hash
  from public.minecraft_auth_credentials c
  where c.user_id=p_user_id
  for update;

  if v_hash is null then
    return jsonb_build_object('error','AUTH_NOT_CONFIGURED');
  end if;

  if p_current_password is null or extensions.crypt(p_current_password,v_hash) <> v_hash then
    return jsonb_build_object('error','CURRENT_PASSWORD_INVALID');
  end if;

  update public.minecraft_auth_credentials
  set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
      failed_attempts=0,
      locked_until=null,
      updated_at=now()
  where user_id=p_user_id;

  return jsonb_build_object('ok',true,'configured',true);
end;
$function$;

create or replace function public.mc_auth_login(
  p_nickname text,
  p_minecraft_uuid uuid,
  p_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_platform text;
  v_bound_uuid uuid;
  v_hash text;
  v_failed integer;
  v_locked_until timestamptz;
  v_attempts integer;
begin
  select u.id,u.platform,u.minecraft_uuid
    into v_user_id,v_platform,v_bound_uuid
  from public.users u
  where u.deleted_at is null
    and lower(trim(coalesce(u.minecraft_nickname,'')))=lower(trim(p_nickname))
    and u.status='ACCEPTED'
    and u.is_whitelisted=true
    and u.is_banned=false
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('error','USER_NOT_FOUND');
  end if;

  if upper(coalesce(v_platform,'')) <> 'JAVA' then
    return jsonb_build_object('error','PLATFORM_NOT_JAVA');
  end if;

  if v_bound_uuid is not null and v_bound_uuid <> p_minecraft_uuid then
    return jsonb_build_object('error','IDENTITY_MISMATCH');
  end if;

  select c.password_hash,c.failed_attempts,c.locked_until
    into v_hash,v_failed,v_locked_until
  from public.minecraft_auth_credentials c
  where c.user_id=v_user_id
  for update;

  if v_hash is null then
    return jsonb_build_object('error','AUTH_NOT_CONFIGURED');
  end if;

  if v_locked_until is not null and v_locked_until > now() then
    return jsonb_build_object('error','AUTH_LOCKED','locked_until',v_locked_until);
  end if;

  if p_password is not null and extensions.crypt(p_password,v_hash)=v_hash then
    update public.minecraft_auth_credentials
    set failed_attempts=0,locked_until=null,last_login_at=now(),updated_at=now()
    where user_id=v_user_id;

    return jsonb_build_object('ok',true,'authenticated',true,'user_id',v_user_id);
  end if;

  v_attempts:=least(coalesce(v_failed,0)+1,5);
  if v_attempts >= 5 then
    update public.minecraft_auth_credentials
    set failed_attempts=v_attempts,locked_until=now()+interval '10 minutes',updated_at=now()
    where user_id=v_user_id;

    return jsonb_build_object(
      'error','AUTH_LOCKED',
      'locked_until',now()+interval '10 minutes'
    );
  end if;

  update public.minecraft_auth_credentials
  set failed_attempts=v_attempts,updated_at=now()
  where user_id=v_user_id;

  return jsonb_build_object('error','INVALID_PASSWORD','attempts_remaining',5-v_attempts);
end;
$function$;

create or replace function public.participant_get_minecraft_auth_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_platform text;
  v_nickname text;
  v_configured boolean;
  v_locked_until timestamptz;
  v_last_login timestamptz;
begin
  select u.id,upper(coalesce(u.platform::text,'')),u.minecraft_nickname
    into v_user_id,v_platform,v_nickname
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('error','USER_NOT_LINKED');
  end if;

  select count(*) > 0,max(c.locked_until),max(c.last_login_at)
    into v_configured,v_locked_until,v_last_login
  from public.minecraft_auth_credentials c
  where c.user_id=v_user_id;

  return jsonb_build_object(
    'ok',true,
    'platform',v_platform,
    'minecraft_nickname',v_nickname,
    'configured',coalesce(v_configured,false),
    'locked_until',v_locked_until,
    'last_login_at',v_last_login
  );
end;
$function$;

create or replace function public.participant_set_minecraft_password(
  p_current_password text,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_existing boolean;
  v_result jsonb;
begin
  select u.id into v_user_id
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
    and u.status='ACCEPTED'
    and u.is_whitelisted=true
    and u.is_banned=false
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('error','PLAYER_ACCESS_REQUIRED');
  end if;

  select exists(select 1 from public.minecraft_auth_credentials c where c.user_id=v_user_id)
    into v_existing;

  if v_existing then
    return public.mc_auth_change_password(v_user_id,p_current_password,p_new_password);
  end if;

  return public.mc_auth_set_password(v_user_id,p_new_password);
end;
$function$;

create or replace function public.bot_get_minecraft_auth_status(
  p_tg_id bigint
) returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select case when u.id is null then jsonb_build_object('error','USER_NOT_FOUND')
    else jsonb_build_object(
      'ok',true,
      'platform',upper(coalesce(u.platform::text,'')),
      'minecraft_nickname',u.minecraft_nickname,
      'configured',exists(
        select 1 from public.minecraft_auth_credentials c where c.user_id=u.id
      ),
      'last_login_at',(
        select c.last_login_at from public.minecraft_auth_credentials c where c.user_id=u.id
      )
    )
  end
  from (select * from public.users where telegram_id=p_tg_id and deleted_at is null limit 1) u;
$function$;

revoke all on function public.mc_auth_status(text,uuid) from public,anon,authenticated;
revoke all on function public.mc_auth_set_password(uuid,text) from public,anon,authenticated;
revoke all on function public.mc_auth_change_password(uuid,text,text) from public,anon,authenticated;
revoke all on function public.mc_auth_login(text,uuid,text) from public,anon,authenticated;
revoke all on function public.participant_get_minecraft_auth_status() from public,anon;
revoke all on function public.participant_set_minecraft_password(text,text) from public,anon;
revoke all on function public.bot_get_minecraft_auth_status(bigint) from public,anon,authenticated;

grant execute on function public.mc_auth_status(text,uuid) to service_role;
grant execute on function public.mc_auth_set_password(uuid,text) to service_role;
grant execute on function public.mc_auth_change_password(uuid,text,text) to service_role;
grant execute on function public.mc_auth_login(text,uuid,text) to service_role;
grant execute on function public.participant_get_minecraft_auth_status() to authenticated,service_role;
grant execute on function public.participant_set_minecraft_password(text,text) to authenticated,service_role;
grant execute on function public.bot_get_minecraft_auth_status(bigint) to service_role;
