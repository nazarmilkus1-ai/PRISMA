-- PRISMA 2.0.0: harden Minecraft identity lookup without making nickname
-- the only long-term identity boundary.
--
-- Java authentication is delegated to SimpleLogin by the plugin. When a
-- minecraft_uuid is already bound, the login RPC additionally enforces it.
-- Existing unbound users remain compatible and are not mass-bound here.

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

revoke all on function public.get_minecraft_user(text)
from public,anon,authenticated;
grant execute on function public.get_minecraft_user(text) to service_role;

revoke all on function public.get_minecraft_user_v2(text,uuid)
from public,anon,authenticated;
grant execute on function public.get_minecraft_user_v2(text,uuid) to service_role;
