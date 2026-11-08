create type application_status as enum ('PENDING', 'ACCEPTED', 'REJECTED');
create type platform_type      as enum ('JAVA', 'BEDROCK');
create type moderation_type    as enum ('WARN', 'MUTE', 'KICK');
create type moderation_source  as enum ('DASHBOARD', 'PLUGIN', 'BOT');
create type report_type        as enum ('BUG', 'SERVER', 'PLAYER');
create type report_status      as enum ('OPEN', 'IN_REVIEW', 'RESOLVED', 'DISMISSED');
create type poll_kind          as enum ('POLL', 'SERVER_RATING');

create table users (
  id                 uuid primary key default gen_random_uuid(),
  telegram_id        bigint unique not null,
  telegram_username  text,
  first_name         text,
  last_name          text,
  full_name          text,
  age                integer,
  minecraft_nickname text,
  platform           platform_type,
  discovery_source   text,
  mojang_uuid        text unique,
  status             application_status not null default 'PENDING',
  is_whitelisted     boolean not null default false,
  is_banned          boolean not null default false,
  ban_reason         text,
  is_muted           boolean not null default false,
  muted_until        timestamptz,
  rating             integer not null default 0,
  activity_score     integer not null default 0,
  last_seen_at       timestamptz,
  clan_id            uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index users_status_idx on users (status);
create index users_whitelisted_idx on users (is_whitelisted);
create index users_nickname_idx on users (lower(minecraft_nickname));

create table applications (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references users (id) on delete cascade,
  full_name          text not null,
  age                integer not null check (age between 6 and 120),
  nickname           text not null,
  platform           platform_type not null,
  discovery_source   text not null,
  status             application_status not null default 'PENDING',
  reviewed_by_tg_id  bigint,
  reviewed_by_name   text,
  reviewed_at        timestamptz,
  rejection_reason   text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index applications_user_idx on applications (user_id);
create index applications_status_idx on applications (status);
create index applications_created_idx on applications (created_at);

create unique index one_pending_application_per_user
  on applications (user_id)
  where (status = 'PENDING');

create table moderation_logs (
  id                uuid primary key default gen_random_uuid(),
  target_id         uuid not null references users (id) on delete cascade,
  issued_by_tg_id   bigint,
  issued_by_name    text,
  type              moderation_type not null,
  reason            text not null,
  duration_minutes  integer,
  expires_at        timestamptz,
  source            moderation_source not null default 'DASHBOARD',
  applied_at        timestamptz,
  created_at        timestamptz not null default now()
);

create index moderation_target_idx on moderation_logs (target_id);
create index moderation_type_idx on moderation_logs (type);
create index moderation_pending_idx on moderation_logs (applied_at) where (applied_at is null);

create table chat_logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users (id) on delete cascade,
  message    text not null,
  world      text,
  created_at timestamptz not null default now()
);

create index chat_logs_user_idx on chat_logs (user_id);
create index chat_logs_created_idx on chat_logs (created_at desc);

create table clans (
  id          uuid primary key default gen_random_uuid(),
  name        text unique not null,
  tag         text unique not null,
  owner_id    uuid unique not null references users (id) on delete cascade,
  description text,
  rating      integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table users
  add constraint users_clan_fk foreign key (clan_id) references clans (id) on delete set null;

create index clans_owner_idx on clans (owner_id);

create table polls (
  id         uuid primary key default gen_random_uuid(),
  question   text not null,
  options    text[] not null default '{}',
  kind       poll_kind not null default 'POLL',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  closes_at  timestamptz
);

create table poll_ratings (
  id            uuid primary key default gen_random_uuid(),
  poll_id       uuid not null references polls (id) on delete cascade,
  user_id       uuid not null references users (id) on delete cascade,
  option_index  integer,
  value         integer check (value between 1 and 5),
  created_at    timestamptz not null default now(),
  unique (poll_id, user_id)
);

create index poll_ratings_poll_idx on poll_ratings (poll_id);

create table reports (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users (id) on delete cascade,
  type             report_type not null,
  target_nickname  text,
  description      text not null,
  status           report_status not null default 'OPEN',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index reports_status_idx on reports (status);

create table bot_sessions (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger users_set_updated_at        before update on users        for each row execute function set_updated_at();
create trigger applications_set_updated_at before update on applications for each row execute function set_updated_at();
create trigger clans_set_updated_at        before update on clans        for each row execute function set_updated_at();
create trigger reports_set_updated_at      before update on reports      for each row execute function set_updated_at();
create trigger bot_sessions_set_updated_at before update on bot_sessions for each row execute function set_updated_at();

alter table users            enable row level security;
alter table applications     enable row level security;
alter table moderation_logs  enable row level security;
alter table chat_logs        enable row level security;
alter table clans            enable row level security;
alter table polls            enable row level security;
alter table poll_ratings     enable row level security;
alter table reports          enable row level security;
alter table bot_sessions     enable row level security;

create policy "admins can read users"            on users            for select to authenticated using (true);
create policy "admins can read applications"     on applications     for select to authenticated using (true);
create policy "admins can read moderation_logs"  on moderation_logs  for select to authenticated using (true);
create policy "admins can read clans"            on clans            for select to authenticated using (true);
create policy "admins can read polls"            on polls            for select to authenticated using (true);
create policy "admins can read poll_ratings"     on poll_ratings     for select to authenticated using (true);
create policy "admins can read reports"          on reports          for select to authenticated using (true);

alter publication supabase_realtime add table applications;
alter publication supabase_realtime add table users;
alter publication supabase_realtime add table moderation_logs;