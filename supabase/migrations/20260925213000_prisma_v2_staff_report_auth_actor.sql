-- PRISMA v2: staff report updates must derive the actor from auth.uid().
-- The previous public signature accepted p_actor_user_id from the client.
-- This migration exposes only the authenticated wrapper.

drop function if exists public.staff_update_report(uuid,uuid,text,text,uuid,jsonb);

create or replace function public.staff_update_report(
  p_report_id uuid,
  p_status text,
  p_internal_notes text default null,
  p_assigned_to uuid default null,
  p_involved_players jsonb default null
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare
  actor_user_id uuid;
begin
  select u.id into actor_user_id
  from public.users u
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;

  if actor_user_id is null then
    raise exception 'STAFF_IDENTITY_NOT_FOUND';
  end if;

  return private.prisma_update_report(
    p_report_id,
    actor_user_id,
    p_status,
    p_internal_notes,
    p_assigned_to,
    p_involved_players
  );
end;
$prisma$;

revoke all on function public.staff_update_report(uuid,text,text,uuid,jsonb)
  from public, anon;
grant execute on function public.staff_update_report(uuid,text,text,uuid,jsonb)
  to authenticated;
