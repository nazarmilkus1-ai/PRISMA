-- PRISMA RBAC v3: reconcile ACL/search_path hardening for already-applied RBAC RPCs.
alter function public.bot_set_staff_rank(bigint,bigint,integer) set search_path='';
revoke execute on function public.bot_set_staff_rank(bigint,bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_set_staff_rank(bigint,bigint,integer) to service_role;

alter function public.bot_set_staff_role(bigint,bigint,text) set search_path='';
revoke execute on function public.bot_set_staff_role(bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_set_staff_role(bigint,bigint,text) to service_role;

alter function public.staff_manage_admin(text,uuid,bigint,text) set search_path='';
revoke execute on function public.staff_manage_admin(text,uuid,bigint,text) from public,anon;
grant execute on function public.staff_manage_admin(text,uuid,bigint,text) to authenticated;

alter function public.mc_get_staff_identity(uuid) set search_path='';
revoke execute on function public.mc_get_staff_identity(uuid) from public,anon,authenticated;
grant execute on function public.mc_get_staff_identity(uuid) to service_role;

alter function public.participant_get_server_role() set search_path='';
revoke execute on function public.participant_get_server_role() from public,anon;
grant execute on function public.participant_get_server_role() to authenticated;

alter function public.bot_list_staff() set search_path='';
revoke execute on function public.bot_list_staff() from public,anon,authenticated;
grant execute on function public.bot_list_staff() to service_role;
