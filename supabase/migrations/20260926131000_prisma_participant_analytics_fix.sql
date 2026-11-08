-- Keep the participant analytics gateway definition reproducible and include sanitized telemetry samples.

create or replace function private.prisma_participant_get_analytics(p_user_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  since_at timestamptz:=now()-interval '30 days';
  rating_rows jsonb;
  kills_rows jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);
  rating_rows:=private.prisma_participant_get_rankings(p_user_id,'rating',8);
  kills_rows:=private.prisma_participant_get_rankings(p_user_id,'kills',8);

  return jsonb_build_object(
    'server',coalesce((
      select jsonb_build_object(
        'current_online',sm.online_players,'current_max',sm.max_players,
        'peak_online',(select coalesce(max(x.online_players),0) from public.server_metrics x where x.recorded_at>=since_at),
        'average_online',(select coalesce(round(avg(x.online_players)),0) from public.server_metrics x where x.recorded_at>=since_at),
        'average_tps',(select round(avg(x.tps),1) from public.server_metrics x where x.recorded_at>=since_at and x.tps is not null),
        'current_memory_mb',sm.memory_used_mb,
        'peak_memory_mb',(select coalesce(max(x.memory_used_mb),0) from public.server_metrics x where x.recorded_at>=since_at)
      ) from public.server_metrics sm order by sm.recorded_at desc limit 1
    ),jsonb_build_object('current_online',0,'current_max',0,'peak_online',0,'average_online',0,'average_tps',null,'current_memory_mb',null,'peak_memory_mb',0)),
    'telemetry',coalesce((
      select jsonb_agg(jsonb_build_object('recorded_at',bucket_time,'online_players',online_players) order by bucket_time)
      from (
        select date_trunc('hour',recorded_at) bucket_time,round(avg(online_players)) online_players
        from public.server_metrics where recorded_at>=since_at
        group by date_trunc('hour',recorded_at)
        order by bucket_time desc limit 72
      ) t
    ),'[]'::jsonb),
    'community',(
      select jsonb_build_object(
        'total_players',count(*),
        'active_players',count(*) filter(where u.last_seen_at>=now()-interval '2 minutes'),
        'average_rating',coalesce(round(avg(u.rating)),0),
        'average_level',coalesce(round(avg(u.level)::numeric,1),0),
        'total_xp',coalesce(sum(u.xp),0)
      )
      from public.users u
      where u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned and u.minecraft_nickname is not null
    ),
    'stats',(
      select jsonb_build_object(
        'kills',coalesce(sum(ps.kills),0),'deaths',coalesce(sum(ps.deaths),0),
        'playtime_minutes',coalesce(sum(ps.playtime_minutes),0),
        'blocks_placed',coalesce(sum(ps.blocks_placed),0),'blocks_broken',coalesce(sum(ps.blocks_broken),0),
        'mobs_killed',coalesce(sum(ps.mobs_killed),0),'distance_walked',coalesce(sum(ps.distance_walked),0),
        'damage_dealt',coalesce(sum(ps.damage_dealt),0),'damage_taken',coalesce(sum(ps.damage_taken),0)
      ) from public.player_stats ps join public.users u on u.id=ps.user_id
      where u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
    ),
    'achievements',(select count(*) from public.user_achievements ua join public.users u on u.id=ua.user_id where u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned),
    'rating_top',rating_rows,'kills_top',kills_rows,
    'my_rating',(
      select 1+count(*) from public.users other
      where other.deleted_at is null and other.status='ACCEPTED' and not other.is_banned and other.minecraft_nickname is not null
        and (other.rating>(select rating from public.users where id=p_user_id)
          or (other.rating=(select rating from public.users where id=p_user_id) and other.id<p_user_id))
    ),
    'my_kills',(
      select 1+count(*) from public.users other left join public.player_stats ops on ops.user_id=other.id
      where other.deleted_at is null and other.status='ACCEPTED' and not other.is_banned and other.minecraft_nickname is not null
        and (coalesce(ops.kills,0)>coalesce((select kills from public.player_stats where user_id=p_user_id),0)
          or (coalesce(ops.kills,0)=coalesce((select kills from public.player_stats where user_id=p_user_id),0) and other.id<p_user_id))
    )
  );
end;
$function$;
