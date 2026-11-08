-- PRISMA v2: keep bot player aggregate reads bounded by their intended limits.

create or replace function public.bot_get_achievements(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(x order by x->>'unlocked_at' desc)
  from (
   select json_build_object(
    'id',a.id,'code',a.code,'title',a.title,'description',a.description,'icon',a.icon,
    'xp_reward',a.xp_reward,'coin_reward',a.coin_reward,'unlocked_at',ua.unlocked_at
   ) x
   from public.user_achievements ua join public.achievements a on a.id=ua.achievement_id
   where ua.user_id=uid
   order by ua.unlocked_at desc
   limit 100
  ) rows_data
 ),'[]'::json);
end;
$function$;

create or replace function public.bot_get_own_punishments(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(x order by x->>'created_at' desc)
  from (
   select json_build_object(
    'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
    'expires_at',m.expires_at,'status',m.status,'applied_at',m.applied_at,'created_at',m.created_at,'source',m.source
   ) x
   from public.moderation_logs m
   where m.target_id=uid and m.type not in ('UNMUTE','UNWARN','UNBAN','WHITELIST','UNWHITELIST')
   order by m.created_at desc limit 20
  ) rows_data
 ),'[]'::json);
end;
$function$;

create or replace function public.bot_get_player_reports(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(x order by x->>'created_at' desc)
  from (
   select json_build_object(
    'id',r.id,'ticket_no',r.ticket_no,'type',r.type,'target_nickname',r.target_nickname,'description',r.description,
    'status',r.status,'priority',r.priority,'category',r.category,'created_at',r.created_at,'updated_at',r.updated_at,'resolved_at',r.resolved_at
   ) x
   from public.reports r
   where r.user_id=uid order by r.created_at desc limit 20
  ) rows_data
 ),'[]'::json);
end;
$function$;

create or replace function public.bot_get_player_appeals(p_tg_id bigint)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
 select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;
 return coalesce((
  select json_agg(x order by x->>'created_at' desc)
  from (
   select json_build_object(
    'id',pa.id,'punishment_id',pa.punishment_id,'reason',pa.reason,'status',pa.status,
    'reviewed_by_tg_id',pa.reviewed_by_tg_id,'review_note',pa.review_note,'created_at',pa.created_at,'updated_at',pa.updated_at
   ) x
   from public.punishment_appeals pa where pa.user_id=uid order by pa.created_at desc limit 20
  ) rows_data
 ),'[]'::json);
end;
$function$;
