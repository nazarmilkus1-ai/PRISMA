-- Staff report: every known person with the facts needed to answer "who is silent, who applied, who did not".
-- Activity = the last message in the community chat (telegram_chat_activity); applied = has any application.
-- Read-only, service_role only.
create or replace function public.bot_activity_report(p_chat_id bigint, p_days integer default 7)
returns json
language sql
stable
security definer
set search_path=''
as $function$
with chat as (
  select a.user_id, max(a.last_message_at) last_chat
  from public.telegram_chat_activity a
  where a.chat_id = p_chat_id
  group by a.user_id
),
base as (
  select
    u.telegram_id as tg_id,
    nullif(u.telegram_username,'') as username,
    coalesce(nullif(u.full_name,''), nullif(u.minecraft_nickname,''), u.telegram_id::text) as name,
    u.status::text as status,
    exists (select 1 from public.applications ap where ap.user_id = u.id) as applied,
    exists (select 1 from public.admins ad where ad.user_id = u.id) as is_staff,
    c.last_chat,
    case when c.last_chat is null then null
         else extract(epoch from (now() - c.last_chat)) / 86400.0 end as days_silent
  from public.users u
  left join chat c on c.user_id = u.id
  where u.deleted_at is null and u.telegram_id > 100000
)
select coalesce(json_agg(json_build_object(
  'tg_id', tg_id, 'username', username, 'name', name, 'status', status, 'applied', applied,
  'is_staff', is_staff, 'last_chat_at', last_chat,
  'days_silent', case when days_silent is null then null else round(days_silent::numeric, 1) end,
  'category', case
     when is_staff then 'staff'
     when status = 'ACCEPTED' and last_chat is null then 'member_never_wrote'
     when status = 'ACCEPTED' and days_silent > greatest(1, coalesce(p_days, 7)) then 'member_silent'
     when status = 'ACCEPTED' then 'member_active'
     when last_chat is null then 'guest_never_wrote'
     when days_silent > greatest(1, coalesce(p_days, 7)) then 'guest_silent'
     else 'guest_active' end
) order by days_silent desc nulls first, name), '[]'::json)
from base;
$function$;

revoke all on function public.bot_activity_report(bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_activity_report(bigint,integer) to service_role;
