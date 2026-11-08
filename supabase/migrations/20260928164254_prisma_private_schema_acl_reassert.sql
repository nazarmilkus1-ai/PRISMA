-- PRISMA 2.0.0: re-assert the private schema client-role lockdown.
revoke usage on schema private from authenticated, anon;
revoke all on all functions in schema private from authenticated, anon;
