-- PRISMA v2: authenticated staff adapter for the canonical application decision.
-- The browser never supplies the actor id. auth.uid() is resolved server-side.

create or replace function public.staff_decide_application(
  p_application_id uuid,
  p_action text,
  p_reason text default null
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

  return private.prisma_decide_application(
    p_application_id,
    actor_user_id,
    p_action,
    p_reason
  );
end;
$prisma$;

revoke all on function public.staff_decide_application(uuid,text,text) from public, anon;
grant execute on function public.staff_decide_application(uuid,text,text) to authenticated;
