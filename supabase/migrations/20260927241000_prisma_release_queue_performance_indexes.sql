-- PRISMA v2: indexes for notification worker claims and trusted moderation polling.

create index if not exists notifications_worker_claim_idx
  on public.notifications (available_at, created_at, id)
  where status='pending' and attempts < 5;

create index if not exists notifications_worker_stale_idx
  on public.notifications (updated_at, attempts, id)
  where status='sending';

create index if not exists moderation_pending_created_idx
  on public.moderation_logs (created_at, id)
  where applied_at is null;

create index if not exists admins_user_role_idx
  on public.admins (user_id, role_id);
