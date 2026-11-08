-- RLS policies on participant-facing tables call this read-only SECURITY DEFINER
-- helper to recognize staff permissions. Policy execution happens as the caller,
-- so the helper must be executable by roles whose policies reference it.
grant execute on function private.has_permission(text) to anon, authenticated;
