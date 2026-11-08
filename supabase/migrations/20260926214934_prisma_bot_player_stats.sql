-- Canonical bot read contract for Minecraft player statistics.

create or replace function private.prisma_bot_get_player_stats(p_tg_id bigint)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  result json;
begin
  select u.id
    into uid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
    and u.status='ACCEPTED'
    and u.is_whitelisted=true
    and u.is_banned=false
  limit 1;

  if uid is null then
    return json_build_object('error','PLAYER_ACCESS_REQUIRED');
  end if;

  select json_build_object(
    'user_id',s.user_id,
    'kills',s.kills,
    'deaths',s.deaths,
    'playtime_minutes',s.playtime_minutes,
    'blocks_placed',s.blocks_placed,
    'blocks_broken',s.blocks_broken,
    'mobs_killed',s.mobs_killed,
    'distance_walked',s.distance_walked,
    'damage_dealt',s.damage_dealt,
    'damage_taken',s.damage_taken,
    'updated_at',s.updated_at
  )
  into result
  from public.player_stats s
  where s.user_id=uid
  limit 1;

  return coalesce(
    result,
    json_build_object(
      'user_id',uid,
      'kills',0,
      'deaths',0,
      'playtime_minutes',0,
      'blocks_placed',0,
      'blocks_broken',0,
      'mobs_killed',0,
      'distance_walked',0,
      'damage_dealt',0,
      'damage_taken',0,
      'updated_at',null
    )
  );
end;
$function$;

create or replace function public.bot_get_player_stats(p_tg_id bigint)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return private.prisma_bot_get_player_stats(p_tg_id);
end;
$function$;

revoke all on function public.bot_get_player_stats(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_player_stats(bigint) to service_role;

revoke all on function private.prisma_bot_get_player_stats(bigint) from public,anon,authenticated;
