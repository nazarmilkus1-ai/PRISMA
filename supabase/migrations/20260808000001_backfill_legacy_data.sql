insert into users (telegram_id, telegram_username, full_name, age, minecraft_nickname, platform, discovery_source, status, is_whitelisted)
select
  u.telegram_id,
  u.username,
  coalesce(u.username, a.mc_nick, 'Без имени'),
  coalesce(nullif(a.answers ->> 'experience', '')::int, 18),
  a.mc_nick,
  case when a.answers ->> 'edition' ilike '%java%' then 'JAVA'::platform_type else 'BEDROCK'::platform_type end,
  coalesce(a.answers ->> 'source', 'не указано'),
  case a.status when 'approved' then 'ACCEPTED'::application_status
                when 'rejected' then 'REJECTED'::application_status
                else 'PENDING'::application_status end,
  (a.status = 'approved')
from applications_legacy_v0 a
join users_legacy_v0 u on u.telegram_id = a.user_id
on conflict (telegram_id) do nothing;

insert into applications (user_id, full_name, age, nickname, platform, discovery_source, status, reviewed_by_tg_id, created_at)
select
  new_u.id,
  new_u.full_name,
  new_u.age,
  a.mc_nick,
  new_u.platform,
  new_u.discovery_source,
  new_u.status,
  a.reviewed_by,
  a.created_at
from applications_legacy_v0 a
join users_legacy_v0 legacy_u on legacy_u.telegram_id = a.user_id
join users new_u on new_u.telegram_id = legacy_u.telegram_id
on conflict do nothing;