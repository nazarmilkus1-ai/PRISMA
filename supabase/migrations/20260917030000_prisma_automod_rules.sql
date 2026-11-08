-- Full per-chat automoderation rules.
-- Safe to apply to existing installations: only additive columns/constraints.

alter table public.chat_settings
  add column if not exists links_action text not null default 'warn',
  add column if not exists caps_action text not null default 'warn',
  add column if not exists flood_action text not null default 'mute',
  add column if not exists profanity_action text not null default 'warn',
  add column if not exists media_action text not null default 'off',
  add column if not exists repeat_warn_action text not null default 'mute',
  add column if not exists caps_threshold integer not null default 70,
  add column if not exists flood_messages integer not null default 5,
  add column if not exists flood_window_seconds integer not null default 8;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chat_settings_caps_threshold_check') then
    alter table public.chat_settings add constraint chat_settings_caps_threshold_check check (caps_threshold between 50 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chat_settings_flood_messages_check') then
    alter table public.chat_settings add constraint chat_settings_flood_messages_check check (flood_messages between 2 and 30);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chat_settings_flood_window_check') then
    alter table public.chat_settings add constraint chat_settings_flood_window_check check (flood_window_seconds between 2 and 60);
  end if;
end $$;
