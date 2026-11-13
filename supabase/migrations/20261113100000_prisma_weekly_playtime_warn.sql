-- PRISMA 2.1.0: weekly activity check. Players who spent less than N minutes in Minecraft during the last
-- p_days days are returned as warning candidates; the bot decides, applies safeguards and issues the WARN
-- through the normal punishment RPC. This function only READS.
-- Playtime comes from JOIN/QUIT events (a session without QUIT is capped at 4 hours: crash/restart).
-- Not applied to production by the repository change.

create or replace function public.bot_weekly_inactivity_candidates(
  p_days integer default 7,
  p_min_minutes integer default 60
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  window_start timestamptz;
  joins_count integer;
  players_count integer;
  rows_data json;
begin
  if p_days is null or p_days<1 or p_days>31 then raise exception 'INVALID_WINDOW'; end if;
  if p_min_minutes is null or p_min_minutes<1 or p_min_minutes>10080 then raise exception 'INVALID_THRESHOLD'; end if;
  window_start := now()-make_interval(days=>p_days);

  select count(*),count(distinct e.user_id) into joins_count,players_count
  from public.minecraft_events e
  where e.event_type='JOIN' and e.created_at>=window_start;

  with ev as (
    select e.user_id,e.event_type,e.created_at,
           lead(e.event_type) over w as next_type,
           lead(e.created_at) over w as next_at
    from public.minecraft_events e
    where e.event_type in ('JOIN','QUIT')
      and e.user_id is not null
      and e.created_at>=window_start-interval '1 day'
    window w as (partition by e.user_id order by e.created_at)
  ),
  sessions as (
    select user_id,
           greatest(created_at,window_start) as s,
           least(
             case when next_type='QUIT' then next_at else created_at+interval '4 hours' end,
             now()
           ) as e
    from ev
    where event_type='JOIN'
  ),
  played as (
    select user_id,
           coalesce(sum(greatest(0,extract(epoch from (e-s))/60)),0)::integer as minutes
    from sessions
    group by user_id
  )
  select coalesce(json_agg(json_build_object(
           'tg_id',u.telegram_id,
           'nickname',u.minecraft_nickname,
           'minutes',coalesce(p.minutes,0),
           'active_warns',private.prisma_active_warning_count(u.id)
         ) order by coalesce(p.minutes,0),u.minecraft_nickname),'[]'::json)
  into rows_data
  from public.users u
  left join played p on p.user_id=u.id
  where u.deleted_at is null
    and u.status='ACCEPTED'
    and u.is_whitelisted
    and not coalesce(u.is_banned,false)
    and u.telegram_id is not null
    and u.created_at<now()-interval '7 days'
    and not exists (select 1 from public.admins a where a.user_id=u.id)
    and coalesce(p.minutes,0)<p_min_minutes
    and not exists (
      select 1 from public.moderation_logs m
      where m.target_id=u.id
        and m.source_type='AUTO_INACTIVITY'
        and m.created_at>now()-interval '6 days'
    );

  return json_build_object('window_days',p_days,'min_minutes',p_min_minutes,'joins',joins_count,'players',players_count,'candidates',rows_data);
end;
$function$;

revoke all on function public.bot_weekly_inactivity_candidates(integer,integer) from public,anon,authenticated;
grant execute on function public.bot_weekly_inactivity_candidates(integer,integer) to service_role;
