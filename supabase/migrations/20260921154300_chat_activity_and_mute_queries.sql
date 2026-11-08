create or replace function public.bot_get_chat_warnings(p_chat_id bigint,p_user_tg_id bigint)
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.created_at desc),'[]'::json)
 from (
  select m.id,m.type,m.reason,m.duration_minutes,m.expires_at,m.created_at,m.issued_by_tg_id
  from public.moderation_logs m join public.users u on u.id=m.target_id
  where m.chat_id=p_chat_id and u.telegram_id=p_user_tg_id and m.type='WARN' and m.status='ACTIVE' and m.revoked=false
    and (m.expires_at is null or m.expires_at>now())
  limit 20
 ) x $$;

create or replace function public.bot_list_inactive_members(p_days integer,p_limit integer default 50)
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.last_seen_at asc nulls first),'[]'::json)
 from (
  select u.id,u.telegram_id as tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         u.community_first_seen_at,u.community_last_seen_at as last_seen_at
  from public.users u
  where u.deleted_at is null and u.community_is_member=true
    and (u.community_last_seen_at is null or u.community_last_seen_at < now()-make_interval(days=>greatest(1,p_days)))
  order by u.community_last_seen_at asc nulls first
  limit greatest(1,least(coalesce(p_limit,50),200))
 ) x $$;