-- Allow multiple Telegram groups to have independent automoderation settings.
-- The legacy boolean `id` was the primary key and defaulted to TRUE, which
-- made a second chat collide even when chat_id itself was unique.

alter table public.chat_settings
  add column if not exists row_id uuid default gen_random_uuid();

update public.chat_settings
set row_id = gen_random_uuid()
where row_id is null;

alter table public.chat_settings
  alter column row_id set not null;

alter table public.chat_settings
  drop constraint if exists chat_settings_pkey;

alter table public.chat_settings
  add constraint chat_settings_pkey primary key (row_id);
