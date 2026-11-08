-- PRISMA v2: public SECURITY DEFINER regression guard.
-- Only the intentionally public read gateways may be executable by anon.
-- Keep this check in the migration stream so a future migration cannot silently
-- expose a privileged RPC through PostgREST.

do $$
declare
  unexpected text;
begin
  select string_agg(
    n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
    ', ' order by p.proname
  )
  into unexpected
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and has_function_privilege('anon',p.oid,'EXECUTE')
    and not (
      (p.proname='get_public_event_details' and pg_get_function_identity_arguments(p.oid)='p_slug text')
      or (p.proname='get_public_map_data' and pg_get_function_identity_arguments(p.oid)='')
      or (p.proname='get_public_polls' and pg_get_function_identity_arguments(p.oid)='p_limit integer')
      or (p.proname='get_public_server_status' and pg_get_function_identity_arguments(p.oid)='')
    );

  if unexpected is not null then
    raise exception 'UNEXPECTED_PUBLIC_SECURITY_DEFINER_RPC: %', unexpected;
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname='get_public_event_details'
      and pg_get_function_identity_arguments(p.oid)='p_slug text'
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'PUBLIC_EVENT_GATEWAY_MISSING';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname='get_public_map_data'
      and pg_get_function_identity_arguments(p.oid)=''
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'PUBLIC_MAP_GATEWAY_MISSING';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname='get_public_polls'
      and pg_get_function_identity_arguments(p.oid)='p_limit integer'
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'PUBLIC_POLLS_GATEWAY_MISSING';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname='get_public_server_status'
      and pg_get_function_identity_arguments(p.oid)=''
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'PUBLIC_SERVER_GATEWAY_MISSING';
  end if;
end
$$;
