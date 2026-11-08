-- PRISMA control-plane expansion.
-- Additive only: no DROP/TRUNCATE and no destructive data migration.
-- The service role is used by the bot/panel for the operational tables below.

create extension if not exists pgcrypto;

-- Existing dashboard code stores these moderation lifecycle fields.
alter table public.moderation_logs
  add column if not exists revoked boolean not null default false,
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_by_tg_id bigint,
  add column if not exists revoked_by_name text;

create index if not exists moderation_logs_target_active_idx
  on public.moderation_logs(target_id, type, revoked, created_at desc);

-- The panel's news editor has a typed kind and remembers the author display name.
alter table public.news
  add column if not exists kind text not null default 'NEWS',
  add column if not exists created_by_name text;

alter table public.news
  drop constraint if exists news_kind_check;
alter table public.news
  add constraint news_kind_check check (kind in ('NEWS', 'UPDATE'));

create index if not exists news_kind_idx on public.news(kind, is_published, created_at desc);

-- Telegram-to-panel authentication handshake.
create table if not exists public.login_codes (
  id uuid primary key default gen_random_uuid(),
  session_token text unique not null,
  code text,
  telegram_id bigint,
  status text not null default 'pending',
  attempts integer not null default 0 check (attempts >= 0 and attempts <= 5),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('pending', 'sent', 'verified', 'expired'))
);

create index if not exists login_codes_active_idx on public.login_codes(session_token, status, expires_at);

drop trigger if exists login_codes_set_updated_at on public.login_codes;
create trigger login_codes_set_updated_at
before update on public.login_codes
for each row execute function public.set_updated_at();

alter table public.login_codes enable row level security;

-- Persistent audit trail for every privileged control-plane action.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.users(id) on delete set null,
  actor_telegram_id bigint,
  actor_name text,
  action text not null,
  resource text not null,
  resource_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);
create index if not exists audit_logs_resource_idx on public.audit_logs(resource, resource_id, created_at desc);
create index if not exists audit_logs_actor_idx on public.audit_logs(actor_telegram_id, created_at desc);
alter table public.audit_logs enable row level security;

-- Login/session history. Tokens are never stored here.
create table if not exists public.login_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  telegram_id bigint,
  auth_user_id uuid,
  method text not null default 'telegram_code',
  ip_hash text,
  user_agent text,
  success boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists login_history_user_idx on public.login_history(user_id, created_at desc);
create index if not exists login_history_created_idx on public.login_history(created_at desc);
alter table public.login_history enable row level security;

-- Queue for user-facing and operator-facing notifications.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  telegram_id bigint,
  channel text not null default 'telegram',
  kind text not null,
  title text,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('pending', 'sending', 'sent', 'failed', 'cancelled'))
);

create index if not exists notifications_queue_idx on public.notifications(status, available_at, created_at);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);
alter table public.notifications enable row level security;

drop trigger if exists notifications_set_updated_at on public.notifications;
create trigger notifications_set_updated_at
before update on public.notifications
for each row execute function public.set_updated_at();

-- Server heartbeat/metrics written by the Minecraft plugin integration.
create table if not exists public.server_metrics (
  id uuid primary key default gen_random_uuid(),
  server_name text not null default 'primary',
  online_players integer not null default 0 check (online_players >= 0),
  max_players integer not null default 0 check (max_players >= 0),
  tps numeric(5,2),
  cpu_percent numeric(5,2),
  memory_used_mb integer,
  memory_max_mb integer,
  uptime_seconds bigint,
  version text,
  world text,
  recorded_at timestamptz not null default now()
);

create index if not exists server_metrics_recent_idx on public.server_metrics(server_name, recorded_at desc);
alter table public.server_metrics enable row level security;

-- Scheduler definitions for broadcasts, backups and recurring maintenance.
create table if not exists public.scheduled_jobs (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  job_type text not null,
  cron text,
  payload jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  last_run_at timestamptz,
  next_run_at timestamptz,
  last_status text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists scheduled_jobs_next_idx on public.scheduled_jobs(enabled, next_run_at);
alter table public.scheduled_jobs enable row level security;

drop trigger if exists scheduled_jobs_set_updated_at on public.scheduled_jobs;
create trigger scheduled_jobs_set_updated_at
before update on public.scheduled_jobs
for each row execute function public.set_updated_at();

-- Mass-message campaigns with delivery accounting.
create table if not exists public.broadcasts (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references public.admins(id) on delete set null,
  title text not null,
  body text not null,
  target_filter jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  scheduled_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  recipients_count integer not null default 0,
  sent_count integer not null default 0,
  failed_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('draft', 'scheduled', 'sending', 'sent', 'failed', 'cancelled'))
);

create index if not exists broadcasts_schedule_idx on public.broadcasts(status, scheduled_at);
alter table public.broadcasts enable row level security;

drop trigger if exists broadcasts_set_updated_at on public.broadcasts;
create trigger broadcasts_set_updated_at
before update on public.broadcasts
for each row execute function public.set_updated_at();

-- Backup/restore bookkeeping. The actual archive stays in the configured backup store.
create table if not exists public.backup_runs (
  id uuid primary key default gen_random_uuid(),
  backup_type text not null default 'scheduled',
  storage_key text,
  status text not null default 'started',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  size_bytes bigint,
  checksum text,
  error text,
  metadata jsonb not null default '{}'::jsonb,
  check (status in ('started', 'success', 'failed'))
);

create index if not exists backup_runs_recent_idx on public.backup_runs(started_at desc);
alter table public.backup_runs enable row level security;

-- Explicitly keep operational tables service-role-only at the database layer.
revoke all on public.login_codes, public.audit_logs, public.login_history,
  public.notifications, public.server_metrics, public.scheduled_jobs,
  public.broadcasts, public.backup_runs from anon, authenticated;

-- Helpful cleanup support: old login handshakes can be removed by the scheduler.
create or replace function public.prisma_cleanup_login_codes()
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare deleted_count integer;
begin
  delete from public.login_codes
  where (expires_at < now() - interval '1 hour')
     or status in ('verified', 'expired') and updated_at < now() - interval '1 hour';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.prisma_cleanup_login_codes() to service_role;
