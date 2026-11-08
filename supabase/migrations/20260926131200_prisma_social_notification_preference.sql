alter table public.notification_preferences
  add column if not exists social boolean not null default true;

update public.notification_preferences
set social=true
where social is null;