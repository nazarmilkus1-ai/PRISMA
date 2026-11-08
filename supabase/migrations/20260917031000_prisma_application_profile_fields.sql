-- Normalize application/user profile fields used by the admin card and player profile.
-- Existing rows are preserved; new fields remain nullable where historical data may not exist.

alter table public.users
  add column if not exists birth_date date;

alter table public.applications
  add column if not exists birth_date date,
  add column if not exists goal text,
  add column if not exists about text;

create index if not exists applications_created_at_idx
  on public.applications (created_at desc);

create index if not exists applications_status_created_at_idx
  on public.applications (status, created_at desc);

create index if not exists users_minecraft_nickname_idx
  on public.users (minecraft_nickname)
  where minecraft_nickname is not null;

create index if not exists users_telegram_username_lower_idx
  on public.users (lower(telegram_username))
  where telegram_username is not null;
