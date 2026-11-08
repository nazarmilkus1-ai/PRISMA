-- PRISMA Minecraft heartbeat and canonical nickname lookup.
CREATE OR REPLACE FUNCTION public.prisma_clear_legacy_mojang_uuid()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  NEW.mojang_uuid := NULL;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_minecraft_user(p_nickname text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare result_row public.users%rowtype;
begin
  select *
    into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname)) = lower(trim(p_nickname))
  limit 1;

  if not found then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  return json_build_object(
    'id',result_row.id,
    'telegram_id',result_row.telegram_id,
    'minecraft_nickname',result_row.minecraft_nickname,
    'clan_id',result_row.clan_id,
    'muted_until',result_row.muted_until,
    'status',result_row.status,
    'is_whitelisted',result_row.is_whitelisted,
    'is_banned',result_row.is_banned,
    'ban_reason',result_row.ban_reason
  );
end;
$function$;
REVOKE ALL ON FUNCTION public.get_minecraft_user(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_minecraft_user(text) TO service_role;

CREATE OR REPLACE FUNCTION public.touch_online_players(p_nicknames text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare affected integer:=0;
begin
  if p_nicknames is null or cardinality(p_nicknames)=0 then return 0; end if;
  update public.users u
     set last_seen_at=now(),
         last_login_at=now(),
         updated_at=now()
   where u.deleted_at is null
     and u.status='ACCEPTED'
     and u.is_whitelisted
     and exists (
       select 1
       from unnest(p_nicknames) n(nick)
       where lower(trim(nick))=lower(trim(u.minecraft_nickname))
     );
  get diagnostics affected=row_count;
  return affected;
end;
$function$;
REVOKE ALL ON FUNCTION public.touch_online_players(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_online_players(text[]) TO service_role;
