-- PRISMA 2.0.0: future public objects must remain private until explicitly exposed.
-- Existing grants are intentionally untouched; this only hardens defaults for objects
-- created by the postgres migration owner in the exposed public schema.

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke usage, select, update on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;
