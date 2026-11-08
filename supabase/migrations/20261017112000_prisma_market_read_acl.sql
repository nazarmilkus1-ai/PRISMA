-- PRISMA market is restricted to accepted, whitelisted community members.
-- The website uses participant-scoped market RPCs after checking membership.
-- Remove the obsolete public read gateway and its helper from public API roles.
revoke all on function private.prisma_public_get_market(text, text, integer)
  from public, anon, authenticated;

revoke all on function public.get_public_market(text, text, integer)
  from public, anon, authenticated;
