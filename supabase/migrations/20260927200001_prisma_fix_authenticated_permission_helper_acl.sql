-- PRISMA v2: allow authenticated RLS policies to invoke the private
-- permission helper. Anonymous users must remain unable to execute it.
-- The function derives the caller from auth.uid() and only returns their
-- effective permission, so no privileged dataset is exposed.

grant usage on schema private to authenticated;
grant execute on function private.has_permission(text) to authenticated;
revoke usage on schema private from anon;
revoke execute on function private.has_permission(text) from anon,public;
