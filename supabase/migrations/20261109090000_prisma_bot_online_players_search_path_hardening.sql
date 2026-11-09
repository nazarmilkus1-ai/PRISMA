-- Harden the SECURITY DEFINER online roster RPC against search_path object shadowing.
-- All application relations are schema-qualified; pg_catalog functions remain available implicitly.

create or replace function public.bot_get_online_players()
returns json
language sql
security definer
set search_path = ''
as $function$
  select coalesce(
    json_agg(
      json_build_object(
        'minecraft_nickname', u.minecraft_nickname,
        'platform', u.platform
      )
      order by lower(u.minecraft_nickname)
    ),
    '[]'::json
  )
  from public.users u
  where u.deleted_at is null
    and u.status = 'ACCEPTED'
    and u.is_whitelisted
    and u.last_seen_at > now() - interval '90 seconds';
$function$;

revoke all on function public.bot_get_online_players() from public, anon, authenticated;
grant execute on function public.bot_get_online_players() to service_role;
