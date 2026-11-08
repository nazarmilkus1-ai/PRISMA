create or replace function public.bot_active_chat_users(
  p_chat_id bigint,
  p_minutes integer default 10,
  p_limit integer default 50
)
returns json
language sql
security definer
set search_path=public
as $function$
 select coalesce(json_agg(x order by x.last_message_at desc),'[]'::json)
 from (
  select u.telegram_id as tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         max(a.last_message_at) as last_message_at,sum(a.message_count)::integer as messages
  from public.telegram_chat_activity a
  join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id
    and a.last_message_at >= now()-make_interval(mins=>greatest(1,least(coalesce(p_minutes,10),60)))
    and u.deleted_at is null
  group by u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
  order by last_message_at desc
  limit greatest(1,least(coalesce(p_limit,50),100))
 ) x;
$function$;

revoke execute on function public.bot_active_chat_users(bigint,integer,integer) from public,anon,authenticated;
grant execute on function public.bot_active_chat_users(bigint,integer,integer) to service_role;
