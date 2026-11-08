-- PRISMA admin: email-вход вместо Telegram Login Widget.
--
-- Allow-лист администраторов. Проверяется в двух местах в коде админки:
-- src/app/auth/callback/route.ts (после входа по magic link) и proxy.ts
-- (на каждый запрос к /dashboard/*, для мгновенного отзыва доступа).
-- Также можно перечислить email'ы через переменную окружения ADMIN_EMAILS
-- (через запятую) — тогда эта таблица не обязательна, но удобна, если
-- список меняется чаще, чем деплой.

create table if not exists public.admin_emails (
  email text primary key,
  added_at timestamptz not null default now(),
  note text
);

alter table public.admin_emails enable row level security;

-- Только service_role (сервер приложения) читает эту таблицу.
drop policy if exists "admin_emails_service_role" on public.admin_emails;
create policy "admin_emails_service_role"
  on public.admin_emails
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Пример заполнения (раскомментируйте и подставьте реальные email):
-- insert into public.admin_emails (email) values
--   ('owner@example.com'),
--   ('moderator@example.com')
-- on conflict (email) do nothing;
