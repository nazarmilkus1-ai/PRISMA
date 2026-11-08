-- PRISMA v2: keep the entire Minecraft integration RPC surface server-only.
-- The Paper plugin authenticates with service_role and never calls these from
-- browser/participant contexts.

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (
        p.proname like 'mc_%'
        or p.proname in (
          'get_minecraft_user',
          'record_activity_event',
          'touch_online_players',
          'upsert_server_heartbeat'
        )
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      f.signature
    );
    execute format(
      'grant execute on function %s to service_role',
      f.signature
    );
  end loop;
end
$$;
