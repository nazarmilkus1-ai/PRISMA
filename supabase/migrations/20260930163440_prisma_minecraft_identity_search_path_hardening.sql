-- PRISMA 2.0.0: finish Minecraft SECURITY DEFINER hardening and enforce
-- a database-level unique Minecraft UUID binding.

create unique index if not exists users_minecraft_uuid_unique
  on public.users (minecraft_uuid)
  where minecraft_uuid is not null;

create or replace function public.get_minecraft_user(p_nickname text)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare result_row public.users%rowtype;
begin
  select * into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_nickname))
  limit 1;

  if not found then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  return json_build_object(
    'id',result_row.id,
    'telegram_id',result_row.telegram_id,
    'minecraft_nickname',result_row.minecraft_nickname,
    'minecraft_uuid',result_row.minecraft_uuid,
    'clan_id',result_row.clan_id,
    'is_muted',result_row.is_muted,
    'muted_until',result_row.muted_until,
    'status',result_row.status,
    'platform',result_row.platform,
    'is_whitelisted',result_row.is_whitelisted,
    'is_banned',result_row.is_banned,
    'ban_reason',result_row.ban_reason
  );
end;
$function$;

create or replace function public.get_minecraft_user_v2(
  p_nickname text,
  p_minecraft_uuid uuid
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare result_row public.users%rowtype;
begin
  if p_nickname is null or btrim(p_nickname)='' then
    return json_build_object('error','INVALID_MINECRAFT_NICK');
  end if;

  if p_minecraft_uuid is null then
    return json_build_object('error','INVALID_MINECRAFT_UUID');
  end if;

  select * into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_nickname))
  limit 1;

  if not found then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  if result_row.minecraft_uuid is not null
     and result_row.minecraft_uuid <> p_minecraft_uuid then
    return json_build_object('error','MINECRAFT_UUID_MISMATCH');
  end if;

  return json_build_object(
    'id',result_row.id,
    'telegram_id',result_row.telegram_id,
    'minecraft_nickname',result_row.minecraft_nickname,
    'minecraft_uuid',result_row.minecraft_uuid,
    'clan_id',result_row.clan_id,
    'is_muted',result_row.is_muted,
    'muted_until',result_row.muted_until,
    'status',result_row.status,
    'platform',result_row.platform,
    'is_whitelisted',result_row.is_whitelisted,
    'is_banned',result_row.is_banned,
    'ban_reason',result_row.ban_reason
  );
end;
$function$;

create or replace function public.mc_bind_minecraft_identity(
  p_nickname text,
  p_minecraft_uuid uuid,
  p_platform text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  result_row public.users%rowtype;
  normalized_platform text;
begin
  normalized_platform := upper(btrim(coalesce(p_platform, '')));
  if normalized_platform not in ('JAVA', 'BEDROCK') then
    return json_build_object('error', 'INVALID_PLATFORM');
  end if;

  if p_nickname is null or btrim(p_nickname) = '' then
    return json_build_object('error', 'INVALID_MINECRAFT_NICK');
  end if;

  if p_minecraft_uuid is null then
    return json_build_object('error', 'INVALID_MINECRAFT_UUID');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_minecraft_uuid::text));

  select *
    into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname)) = lower(trim(p_nickname))
  for update;

  if not found then
    return json_build_object('error', 'USER_NOT_FOUND');
  end if;

  if result_row.minecraft_uuid is not null
     and result_row.minecraft_uuid <> p_minecraft_uuid then
    return json_build_object('error', 'MINECRAFT_UUID_MISMATCH');
  end if;

  if result_row.platform is not null
     and result_row.platform::text <> normalized_platform then
    return json_build_object('error', 'PLATFORM_MISMATCH');
  end if;

  if exists (
    select 1
    from public.users other_user
    where other_user.deleted_at is null
      and other_user.id <> result_row.id
      and other_user.minecraft_uuid = p_minecraft_uuid
  ) then
    return json_build_object('error', 'MINECRAFT_UUID_ALREADY_BOUND');
  end if;

  update public.users
  set minecraft_uuid = p_minecraft_uuid,
      platform = normalized_platform::public.platform_type
  where id = result_row.id
  returning * into result_row;

  return json_build_object(
    'id', result_row.id,
    'telegram_id', result_row.telegram_id,
    'minecraft_nickname', result_row.minecraft_nickname,
    'minecraft_uuid', result_row.minecraft_uuid,
    'clan_id', result_row.clan_id,
    'is_muted', result_row.is_muted,
    'muted_until', result_row.muted_until,
    'status', result_row.status,
    'platform', result_row.platform,
    'is_whitelisted', result_row.is_whitelisted,
    'is_banned', result_row.is_banned,
    'ban_reason', result_row.ban_reason
  );
end;
$function$;

revoke all on function public.get_minecraft_user(text)
from public, anon, authenticated;
grant execute on function public.get_minecraft_user(text) to service_role;

revoke all on function public.get_minecraft_user_v2(text,uuid)
from public, anon, authenticated;
grant execute on function public.get_minecraft_user_v2(text,uuid) to service_role;

revoke all on function public.mc_bind_minecraft_identity(text,uuid,text)
from public, anon, authenticated;
grant execute on function public.mc_bind_minecraft_identity(text,uuid,text)
to service_role;
