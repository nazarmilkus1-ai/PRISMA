-- PRISMA v2: trusted Telegram player read/write adapters.
-- All functions are service-role-only because the bot is the trusted application boundary.

create or replace function public.bot_get_player_activity_stats(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid; stats json; joins_count integer; quits_count integer; commands_count integer; chat_count integer; last_activity timestamptz;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 select private.prisma_bot_get_player_stats(p_tg_id) into stats;
 select count(*) filter(where upper(event_type)='JOIN'),count(*) filter(where upper(event_type)='QUIT'),
        count(*) filter(where upper(event_type)='COMMAND'),max(created_at)
 into joins_count,quits_count,commands_count,last_activity
 from public.minecraft_events where user_id=uid;
 select count(*) into chat_count from public.chat_logs where user_id=uid;
 return (stats::jsonb || jsonb_build_object(
   'joins',joins_count,'quits',quits_count,'chat',chat_count,'commands',commands_count,'last_activity',last_activity
 ))::json;
end;
$function$;
revoke all on function public.bot_get_player_activity_stats(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_player_activity_stats(bigint) to service_role;

create or replace function public.bot_get_achievements(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(json_build_object(
   'id',a.id,'code',a.code,'title',a.title,'description',a.description,'icon',a.icon,
   'xp_reward',a.xp_reward,'coin_reward',a.coin_reward,'unlocked_at',ua.unlocked_at
  ) order by ua.unlocked_at desc)
  from public.user_achievements ua join public.achievements a on a.id=ua.achievement_id
  where ua.user_id=uid limit 100
 ),'[]'::json);
end;
$function$;
revoke all on function public.bot_get_achievements(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_achievements(bigint) to service_role;

create or replace function public.bot_get_own_punishments(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(json_build_object(
   'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
   'expires_at',m.expires_at,'status',m.status,'applied_at',m.applied_at,'created_at',m.created_at,'source',m.source
  ) order by m.created_at desc)
  from public.moderation_logs m
  where m.target_id=uid and m.type not in ('UNMUTE','UNWARN','UNBAN','WHITELIST','UNWHITELIST')
  limit 20
 ),'[]'::json);
end;
$function$;
revoke all on function public.bot_get_own_punishments(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_own_punishments(bigint) to service_role;

create or replace function public.bot_get_player_reports(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(json_build_object(
   'id',r.id,'ticket_no',r.ticket_no,'type',r.type,'target_nickname',r.target_nickname,'description',r.description,
   'status',r.status,'priority',r.priority,'category',r.category,'created_at',r.created_at,'updated_at',r.updated_at,'resolved_at',r.resolved_at
  ) order by r.created_at desc)
  from public.reports r where r.user_id=uid limit 20
 ),'[]'::json);
end;
$function$;
revoke all on function public.bot_get_player_reports(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_player_reports(bigint) to service_role;

create or replace function public.bot_get_notification_preferences(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 insert into public.notification_preferences(user_id) values(uid) on conflict(user_id) do nothing;
 return (
  select json_build_object(
   'news',news,'events',events,'server_status',server_status,'clan_news',clan_news,
   'social',social,'battles',battles,'market',market,'moderation',moderation,'polls',polls
  )
  from public.notification_preferences where user_id=uid
 );
end;
$function$;
revoke all on function public.bot_get_notification_preferences(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_notification_preferences(bigint) to service_role;

create or replace function public.bot_set_notification_preference(p_tg_id bigint,p_key text,p_enabled boolean)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid; key text:=trim(p_key);
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if key not in ('news','events','server_status','clan_news','social','battles','market','moderation','polls') then raise exception 'INVALID_KEY'; end if;
 insert into public.notification_preferences(user_id) values(uid) on conflict(user_id) do nothing;
 update public.notification_preferences set
  news=case when key='news' then p_enabled else news end,
  events=case when key='events' then p_enabled else events end,
  server_status=case when key='server_status' then p_enabled else server_status end,
  clan_news=case when key='clan_news' then p_enabled else clan_news end,
  social=case when key='social' then p_enabled else social end,
  battles=case when key='battles' then p_enabled else battles end,
  market=case when key='market' then p_enabled else market end,
  moderation=case when key='moderation' then p_enabled else moderation end,
  polls=case when key='polls' then p_enabled else polls end,
  updated_at=now()
 where user_id=uid;
 return public.bot_get_notification_preferences(p_tg_id);
end;
$function$;
revoke all on function public.bot_set_notification_preference(bigint,text,boolean) from public,anon,authenticated;
grant execute on function public.bot_set_notification_preference(bigint,text,boolean) to service_role;

create or replace function public.bot_get_player_appeals(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(json_build_object(
   'id',pa.id,'punishment_id',pa.punishment_id,'reason',pa.reason,'status',pa.status,
   'reviewed_by_tg_id',pa.reviewed_by_tg_id,'review_note',pa.review_note,'created_at',pa.created_at,'updated_at',pa.updated_at
  ) order by pa.created_at desc)
  from public.punishment_appeals pa where pa.user_id=uid limit 20
 ),'[]'::json);
end;
$function$;
revoke all on function public.bot_get_player_appeals(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_player_appeals(bigint) to service_role;

create or replace function public.bot_get_server_metrics()
returns json language plpgsql security definer set search_path=''
as $function$
declare result json;
begin
 select row_to_json(x) into result
 from (
  select server_name,online_players,max_players,tps,cpu_percent,memory_used_mb,memory_max_mb,uptime_seconds,version,world,recorded_at
  from public.server_metrics order by recorded_at desc limit 1
 ) x;
 return coalesce(result,'{}'::json);
end;
$function$;
revoke all on function public.bot_get_server_metrics() from public,anon,authenticated;
grant execute on function public.bot_get_server_metrics() to service_role;

create or replace function public.bot_get_leaderboard(p_field text default 'rating',p_limit integer default 10)
returns json language plpgsql security definer set search_path=''
as $function$
declare result json; field_name text:=lower(trim(p_field)); lim integer:=greatest(1,least(coalesce(p_limit,10),50));
begin
 if field_name not in ('rating','activity_score','xp','level') then raise exception 'INVALID_FIELD'; end if;
 if field_name='rating' then
  select coalesce(json_agg(to_jsonb(x)),'[]'::json) into result from (
   select minecraft_nickname,telegram_username,rating,activity_score,level,xp
   from public.users where status='ACCEPTED' and not is_banned and deleted_at is null order by rating desc,id limit lim
  ) x;
 elsif field_name='activity_score' then
  select coalesce(json_agg(to_jsonb(x)),'[]'::json) into result from (
   select minecraft_nickname,telegram_username,rating,activity_score,level,xp
   from public.users where status='ACCEPTED' and not is_banned and deleted_at is null order by activity_score desc,id limit lim
  ) x;
 elsif field_name='xp' then
  select coalesce(json_agg(to_jsonb(x)),'[]'::json) into result from (
   select minecraft_nickname,telegram_username,rating,activity_score,level,xp
   from public.users where status='ACCEPTED' and not is_banned and deleted_at is null order by xp desc,id limit lim
  ) x;
 else
  select coalesce(json_agg(to_jsonb(x)),'[]'::json) into result from (
   select minecraft_nickname,telegram_username,rating,activity_score,level,xp
   from public.users where status='ACCEPTED' and not is_banned and deleted_at is null order by level desc,xp desc,id limit lim
  ) x;
 end if;
 return result;
end;
$function$;
revoke all on function public.bot_get_leaderboard(text,integer) from public,anon,authenticated;
grant execute on function public.bot_get_leaderboard(text,integer) to service_role;
