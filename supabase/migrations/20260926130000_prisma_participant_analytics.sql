-- Member-only analytics gateway. Returns aggregates and top rows, not raw users/server telemetry.

create or replace function public.participant_get_analytics()
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_analytics(uid);
end;
$function$;

revoke all on function public.participant_get_analytics() from public,anon;
grant execute on function public.participant_get_analytics() to authenticated;
