-- PRISMA: daily onboarding reminder state.
alter table public.users
  add column if not exists onboarding_last_notified_at timestamptz;

update public.users u
set community_first_seen_at = coalesce(u.community_first_seen_at, s.first_seen),
    community_last_seen_at = greatest(coalesce(u.community_last_seen_at, to_timestamp(0)), s.last_seen)
from (
  select user_id, min(created_at) as first_seen, max(created_at) as last_seen
  from public.chat_logs
  where user_id is not null
  group by user_id
) s
where u.id=s.user_id and u.deleted_at is null;

-- bot_touch_user is defined in the previous onboarding migration; this migration
-- only adds the durable 24h notification field and backfills observed chat activity.
