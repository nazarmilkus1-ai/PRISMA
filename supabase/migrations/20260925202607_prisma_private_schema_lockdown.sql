-- PRISMA v2: lock down the private domain schema.
-- Browser roles must use public RPC adapters only. Domain functions are
-- security-definer internals and must never be directly callable by clients.

revoke usage on schema private from authenticated, anon;
revoke all on all functions in schema private from authenticated, anon;
