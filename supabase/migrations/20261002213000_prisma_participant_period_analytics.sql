-- Participant analytics period support.
drop function if exists private.prisma_participant_get_analytics(uuid);

create or replace function private.prisma_participant_get_analytics(
  p_user_id uuid,
  p_period text default '30d'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  period_value text:=case lower(trim(coalesce(p_period,'30d')))
    when '24h' then '24h' when '7d' then '7d' when '30d' then '30d' when 'all' then 'all'
    else '30d' end;
  since_at timestamptz:=case
    when lower(trim(coalesce(p_period,'30d')))='24h' then now()-interval '24 hours'
    when lower(trim(coalesce(p_period,'30d')))='7d' then now()-interval '7 days'
    when lower(trim(coalesce(p_period,'30d')))='30d' then now()-interval '30 days'
    else null end;
  rating_rows jsonb;
  kills_rows jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);
  rating_rows:=private.prisma_participant_get_rankings(p_user_id,'rating',8);
  kills_rows:=private.prisma_participant_get_rankings(p_user_id,'kills',8);

  return jsonb_build_object(
    'period',period_value,
    'server',coalesce((
      select jsonb_build_object(
        'current_online',sm.online_players,'current_max',sm.max_players,
        'peak_online',(select coalesce(max(x.online_players),0) from public.server_metrics x where since_at is null or x.recorded_at>=since_at),
        'average_online',(select coalesce(round(avg(x.online_players)),0) from public.server_metrics x where since_at is null or x.recorded_at>=since_at),
        'average_tps',(select round(avg(x.tps),1) from public.server_metrics x where (since_at is null or x.recorded_at>=since_at) and x.tps is not null),
        'current_memory_mb',sm.memory_used_mb,
        'peak_memory_mb',(select coalesce(max(x.memory_used_mb),0) from public.server_metrics x where since_at is null or x.recorded_at>=since_at)
      )
      from public.server_metrics sm order by sm.recorded_at desc limit 1
    ),jsonb_build_object('current_online',0,'current_max',0,'peak_online',0,'average_online',0,'average_tps',null,'current_memory_mb',null,'peak_memory_mb',0)),
    'telemetry',coalesce((
      select jsonb_agg(jsonb_build_object('recorded_at',bucket_time,'online_players',online_players) order by bucket_time)
      from (
        select date_trunc(case when period_value='24h' then 'hour' else 'day' end,recorded_at) bucket_time,
               round(avg(online_players)) online_players
        from public.server_metrics
        where since_at is null or recorded_at>=since_at
        group by date_trunc(case when period_value='24h' then 'hour' else 'day' end,recorded_at)
        order by bucket_time desc
        limit 120
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
      )
      from public.player_stats ps join public.users u on u.id=ps.user_id
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
      select 1+count(*) from public.users other
      left join public.player_stats ops on ops.user_id=other.id
      where other.deleted_at is null and other.status='ACCEPTED' and not other.is_banned and other.minecraft_nickname is not null
        and (coalesce(ops.kills,0)>coalesce((select kills from public.player_stats where user_id=p_user_id),0)
          or (coalesce(ops.kills,0)=coalesce((select kills from public.player_stats where user_id=p_user_id),0) and other.id<p_user_id))
    )
  );
end;
$function$;

revoke all on function private.prisma_participant_get_analytics(uuid,text) from public,anon,authenticated;

create or replace function public.participant_get_analytics(p_period text default '30d')
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  period_value text:=case lower(trim(coalesce(p_period,'30d')))
    when '24h' then '24h' when '7d' then '7d' when '30d' then '30d' when 'all' then 'all'
    else '30d' end;
  since_at timestamptz;
  chat_activity jsonb;
  my_chat jsonb;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);

  since_at:=case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null end;

  select coalesce(jsonb_agg(x order by x.bucket),'[]'::jsonb) into chat_activity
  from (
    select date_trunc(case when period_value='24h' then 'hour' else 'day' end,g) bucket,
           count(c.id)::integer messages,
           count(distinct c.user_id)::integer unique_players
    from generate_series(
      date_trunc(case when period_value='24h' then 'hour' else 'day' end,
        coalesce(since_at, (select min(created_at) from public.chat_logs), now()-interval '30 days')),
      date_trunc(case when period_value='24h' then 'hour' else 'day' end,now()),
      case when period_value='24h' then interval '1 hour' else interval '1 day' end
    ) g
    left join public.chat_logs c
      on c.created_at>=g
     and c.created_at<g+case when period_value='24h' then interval '1 hour' else interval '1 day' end
    group by 1
    order by 1
    limit 120
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into my_chat
  from (
    select c.id,c.message,c.world,c.created_at
    from public.chat_logs c
    where c.user_id=uid and (since_at is null or c.created_at>=since_at)
    order by c.created_at desc
    limit 500
  ) x;

  return private.prisma_participant_get_analytics(uid,period_value)
    || jsonb_build_object(
      'period',period_value,'from',since_at,'to',now(),
      'chat_activity',chat_activity,'my_chat',my_chat
    );
end;
$function$;

revoke all on function public.participant_get_analytics(text) from public,anon;
grant execute on function public.participant_get_analytics(text) to authenticated;
