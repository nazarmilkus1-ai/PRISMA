create or replace function public.mc_upsert_player_stats(
  p_user_id uuid,
  p_kills integer,
  p_deaths integer,
  p_playtime_minutes bigint,
  p_blocks_placed bigint,
  p_blocks_broken bigint,
  p_mobs_killed bigint,
  p_distance_walked bigint,
  p_damage_dealt bigint,
  p_damage_taken bigint
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
begin
  if not exists(
    select 1 from public.users
    where id=p_user_id
      and status='ACCEPTED'::public.application_status
      and is_whitelisted=true
      and is_banned=false
      and deleted_at is null
  ) then
    raise exception 'USER_NOT_ALLOWED';
  end if;

  insert into public.player_stats(
    user_id,kills,deaths,playtime_minutes,blocks_placed,blocks_broken,
    mobs_killed,distance_walked,damage_dealt,damage_taken,updated_at
  )
  values(
    p_user_id,greatest(0,p_kills),greatest(0,p_deaths),greatest(0,p_playtime_minutes),
    greatest(0,p_blocks_placed),greatest(0,p_blocks_broken),greatest(0,p_mobs_killed),
    greatest(0,p_distance_walked),greatest(0,p_damage_dealt),greatest(0,p_damage_taken),now()
  )
  on conflict(user_id) do update set
    kills=excluded.kills,
    deaths=excluded.deaths,
    playtime_minutes=excluded.playtime_minutes,
    blocks_placed=excluded.blocks_placed,
    blocks_broken=excluded.blocks_broken,
    mobs_killed=excluded.mobs_killed,
    distance_walked=excluded.distance_walked,
    damage_dealt=excluded.damage_dealt,
    damage_taken=excluded.damage_taken,
    updated_at=now();

  return json_build_object('success',true,'user_id',p_user_id);
end;
$function$;

revoke execute on function public.mc_upsert_player_stats(
  uuid,integer,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint
) from public,anon,authenticated;
grant execute on function public.mc_upsert_player_stats(
  uuid,integer,integer,bigint,bigint,bigint,bigint,bigint,bigint,bigint
) to service_role;