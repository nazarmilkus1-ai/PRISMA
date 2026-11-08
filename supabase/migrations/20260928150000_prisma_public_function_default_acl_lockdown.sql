-- PRISMA v2: prevent accidental public EXECUTE grants on future RPCs.
-- All exposed public functions must explicitly grant the roles they need.

alter default privileges for role postgres in schema public
  revoke execute on functions from public;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated;
