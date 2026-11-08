-- PRISMA v2: trigger-only public functions must not be callable as RPCs.
-- These functions are invoked by PostgreSQL triggers and have no participant-facing API.
revoke execute on function public.chat_logs_activity_after_insert()
from public, anon, authenticated, service_role;

revoke execute on function public.prevent_audit_mutation()
from public, anon, authenticated, service_role;

revoke execute on function public.prisma_clear_legacy_mojang_uuid()
from public, anon, authenticated, service_role;
