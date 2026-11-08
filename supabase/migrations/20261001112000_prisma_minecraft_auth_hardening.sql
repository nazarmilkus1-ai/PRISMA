-- PRISMA 2.0.0 native Minecraft auth: post-apply hardening.
-- Keep the server-only RPC contract stable after the initial schema migration.

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
    'user_id',v_user_id,
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
  v_rows integer;
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

  insert into public.minecraft_auth_credentials(user_id,password_hash)
  values(p_user_id,extensions.crypt(p_new_password,extensions.gen_salt('bf',12)))
  on conflict (user_id) do nothing;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return jsonb_build_object('error','AUTH_ALREADY_CONFIGURED');
  end if;

  return jsonb_build_object('ok',true,'configured',true);
end;
$function$;

update public.users u
set last_login_at=c.last_login_at
from public.minecraft_auth_credentials c
where c.user_id=u.id
  and c.last_login_at is not null
  and (u.last_login_at is null or c.last_login_at > u.last_login_at);

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
  v_login_at timestamptz;
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
    v_login_at:=now();
    update public.minecraft_auth_credentials
    set failed_attempts=0,locked_until=null,last_login_at=v_login_at,updated_at=v_login_at
    where user_id=v_user_id;

    update public.users
    set last_login_at=v_login_at,updated_at=v_login_at
    where id=v_user_id;

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

revoke all on function public.mc_auth_status(text,uuid) from public,anon,authenticated;
revoke all on function public.mc_auth_set_password(uuid,text) from public,anon,authenticated;
revoke all on function public.mc_auth_login(text,uuid,text) from public,anon,authenticated;
grant execute on function public.mc_auth_status(text,uuid) to service_role;
grant execute on function public.mc_auth_set_password(uuid,text) to service_role;
grant execute on function public.mc_auth_login(text,uuid,text) to service_role;
