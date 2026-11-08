-- PRISMA 2.0.0: API roles never need to create database objects.
-- Keep schema visibility (USAGE) intact while removing CREATE from public-facing roles.

revoke create on schema public from public, anon, authenticated;
