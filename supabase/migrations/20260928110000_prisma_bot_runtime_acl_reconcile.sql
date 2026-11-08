-- PRISMA v2: keep every public bot_* RPC service-role-only.
-- Bot handlers use the trusted service-role client; participant/browser gateways
-- have their own participant_* / staff_* contracts. Reconcile ACLs dynamically so
-- newly added bot RPCs cannot accidentally inherit PUBLIC EXECUTE.

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname like 'bot_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.signature);
    execute format('grant execute on function %s to service_role', f.signature);
  end loop;
end
$$;
