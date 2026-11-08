-- PRISMA 2.0.0: the private permission helper is intentionally callable
-- by authenticated sessions because RLS policies invoke it directly.
-- The schema stays outside the exposed Data API surface; anon remains denied.

grant usage on schema private to authenticated;
grant execute on function private.has_permission(text) to authenticated;
revoke usage on schema private from anon;
revoke execute on function private.has_permission(text) from anon;
