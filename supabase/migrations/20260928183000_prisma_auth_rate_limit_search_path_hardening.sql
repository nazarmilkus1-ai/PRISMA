-- PRISMA 2.0.0: harden the auth rate-limit SECURITY DEFINER gateway.
-- Keep the function server-only and pin an empty search_path so caller-controlled
-- objects cannot shadow names while the function runs with definer privileges.

create or replace function public.consume_login_rate_limit(
  p_bucket text,
  p_limit integer default 10,
  p_window_seconds integer default 600
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_attempts integer;
  started timestamptz;
begin
  select attempts, window_started_at
    into current_attempts, started
  from public.login_rate_limits
  where bucket = p_bucket
  for update;

  if not found then
    insert into public.login_rate_limits(bucket, attempts, window_started_at)
    values (p_bucket, 1, now())
    on conflict (bucket) do nothing;

    if found then
      return true;
    end if;

    select attempts, window_started_at
      into current_attempts, started
    from public.login_rate_limits
    where bucket = p_bucket
    for update;
  end if;

  if started < now() - pg_catalog.make_interval(secs => p_window_seconds) then
    update public.login_rate_limits
    set attempts = 1, window_started_at = now()
    where bucket = p_bucket;
    return true;
  end if;

  if current_attempts >= p_limit then
    return false;
  end if;

  update public.login_rate_limits
  set attempts = attempts + 1
  where bucket = p_bucket;

  return true;
end;
$function$;

revoke execute on function public.consume_login_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_login_rate_limit(text, integer, integer) to service_role;
