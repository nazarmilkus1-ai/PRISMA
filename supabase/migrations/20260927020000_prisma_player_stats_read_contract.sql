create or replace function public.mc_get_player_stats(p_user_id uuid)
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(
  (
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
      'damage_taken',s.damage_taken
    )
    from public.player_stats s
    where s.user_id=p_user_id
    limit 1
  ),
  json_build_object(
    'user_id',p_user_id,
    'kills',0,'deaths',0,'playtime_minutes',0,
    'blocks_placed',0,'blocks_broken',0,'mobs_killed',0,
    'distance_walked',0,'damage_dealt',0,'damage_taken',0
  )
);
$function$;

revoke execute on function public.mc_get_player_stats(uuid) from public,anon,authenticated;
grant execute on function public.mc_get_player_stats(uuid) to service_role;