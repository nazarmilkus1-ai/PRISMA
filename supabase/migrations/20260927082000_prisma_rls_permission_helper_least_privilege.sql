-- Keep the RLS permission helper callable only by roles whose policies use it.
revoke execute on function private.has_permission(text) from public;
grant execute on function private.has_permission(text) to anon, authenticated;
