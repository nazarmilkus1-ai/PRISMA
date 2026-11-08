-- PRISMA 2.0.0: harden the privileged Telegram login-code gateway.
-- The bot is the only caller; keep the function server-only and pin an empty
-- search_path so caller-controlled objects cannot shadow names under definer rights.

create or replace function public.bot_consume_login_code(
  p_session_token text,
  p_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.login_codes%rowtype;
  v_code text;
begin
  select *
    into v_row
  from public.login_codes
  where session_token = p_session_token
  for update;

  if not found then
    return json_build_object('error', 'SESSION_NOT_FOUND');
  end if;

  if v_row.expires_at < now() then
    update public.login_codes
    set status = 'expired'
    where id = v_row.id;
    return json_build_object('error', 'SESSION_EXPIRED');
  end if;

  if v_row.status not in ('pending', 'sent') then
    return json_build_object('error', 'SESSION_EXPIRED');
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  update public.login_codes
  set code = v_code,
      telegram_id = p_tg_id::text,
      status = 'sent',
      attempts = 0
  where id = v_row.id;

  return json_build_object('success', true, 'code', v_code);
end;
$$;

revoke execute on function public.bot_consume_login_code(text, bigint) from public, anon, authenticated;
grant execute on function public.bot_consume_login_code(text, bigint) to service_role;
