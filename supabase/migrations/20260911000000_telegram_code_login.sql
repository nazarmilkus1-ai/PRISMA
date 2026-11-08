-- PRISMA: единственный способ входа в админ-панель — одноразовый код,
-- который присылает Telegram-бот. Заменяет Telegram Login Widget
-- (oauth.telegram.org) и email/пароль/magic-link.
--
-- Поток:
--   1. Панель: POST /api/auth/telegram/start (panel/src/app/api/auth/telegram/start)
--      вставляет строку со status='pending' и своим session_token,
--      отдаёт пользователю диплинк t.me/<bot>?start=<session_token>.
--   2. Бот: получив "/start <session_token>" (bot/handlers/start.py),
--      вызывает RPC bot_consume_login_code(p_session_token, p_tg_id).
--      Функция сама генерирует 6-значный код, если сессия ещё 'pending'
--      и не просрочена, сохраняет telegram_id и код, ставит status='sent',
--      возвращает код — бот отправляет его пользователю в чат.
--   3. Панель: POST /api/auth/telegram/verify сверяет code, ограничивает
--      число попыток, создаёт сессию Supabase и ставит status='verified'.
--
-- Таблицу читает/пишет только service_role: панель через
-- SUPABASE_SERVICE_ROLE_KEY (createSupabaseAdminClient), бот — через
-- SUPABASE_KEY (config.py), которые оба являются backend-only service-role
-- ключами (см. docs/OPERATIONS.md, раздел Security).

create table if not exists public.login_codes (
  id uuid primary key default gen_random_uuid(),
  session_token text not null unique,
  code text,
  telegram_id text,
  status text not null default 'pending' check (status in ('pending', 'sent', 'verified', 'expired')),
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '5 minutes')
);

create index if not exists login_codes_session_token_idx on public.login_codes (session_token);
create index if not exists login_codes_expires_at_idx on public.login_codes (expires_at);

alter table public.login_codes enable row level security;

drop policy if exists "login_codes_service_role" on public.login_codes;
create policy "login_codes_service_role"
  on public.login_codes
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Вызывается ботом при /start <session_token>. Генерирует код внутри
-- транзакции (row lock через "for update"), чтобы двойной /start от одного
-- пользователя не породил гонку с двумя разными кодами.
create or replace function public.bot_consume_login_code(p_session_token text, p_tg_id bigint)
returns json language plpgsql security definer set search_path = 'public' as $$
declare
  v_row public.login_codes%rowtype;
  v_code text;
begin
  select * into v_row from public.login_codes
    where session_token = p_session_token
    for update;

  if not found then
    return json_build_object('error', 'SESSION_NOT_FOUND');
  end if;

  if v_row.expires_at < now() then
    update public.login_codes set status = 'expired' where id = v_row.id;
    return json_build_object('error', 'SESSION_EXPIRED');
  end if;

  if v_row.status not in ('pending', 'sent') then
    return json_build_object('error', 'SESSION_EXPIRED');
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  update public.login_codes
    set code = v_code, telegram_id = p_tg_id::text, status = 'sent', attempts = 0
    where id = v_row.id;

  return json_build_object('success', true, 'code', v_code);
end;
$$;

-- Необязательно, но полезно: подчищать старые строки раз в релиз или по cron
-- (pg_cron), чтобы таблица не росла бесконечно.
-- delete from public.login_codes where expires_at < now() - interval '1 day';
