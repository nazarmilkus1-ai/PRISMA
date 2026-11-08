-- PRISMA v2: unify legacy RLS/plugin permission helpers with canonical recursive RBAC.

create or replace function private.has_permission(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  select private.prisma_has_user_permission(
    (
      select u.id
      from public.users u
      where u.auth_user_id=(select auth.uid())
        and u.deleted_at is null
      limit 1
    ),
    p_permission_key
  );
$function$;

revoke all on function private.has_permission(text)
from public,anon,authenticated;

create or replace function public.mc_check_staff_permission(
  p_user_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  select private.prisma_has_user_permission(p_user_id,p_permission_key);
$function$;

revoke all on function public.mc_check_staff_permission(uuid,text)
from public,anon,authenticated;

grant execute on function public.mc_check_staff_permission(uuid,text)
to service_role;
