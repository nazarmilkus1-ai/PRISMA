-- PRISMA v2 runtime security hardening.
-- Legacy IRIS archive lookup functions are service-layer only. They are kept
-- in the exposed schema for compatibility with existing bot code but cannot
-- be called by browser roles.

revoke all on function public.bot_get_iris_clan_by_number(integer)
  from public, anon, authenticated;
grant execute on function public.bot_get_iris_clan_by_number(integer)
  to service_role;

revoke all on function public.bot_list_iris_clan_archive()
  from public, anon, authenticated;
grant execute on function public.bot_list_iris_clan_archive()
  to service_role;

-- The canonical staff report function must remain limited to authenticated
-- browser sessions; it resolves the actor from auth.uid() server-side.
revoke all on function public.staff_update_report(uuid,text,text,uuid,jsonb)
  from public, anon;
grant execute on function public.staff_update_report(uuid,text,text,uuid,jsonb)
  to authenticated;

revoke all on function public.staff_decide_application(uuid,text,text)
  from public, anon;
grant execute on function public.staff_decide_application(uuid,text,text)
  to authenticated;
