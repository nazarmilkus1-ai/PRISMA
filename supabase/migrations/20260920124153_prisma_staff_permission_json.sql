create or replace function public.mc_get_staff_permission(
  p_user_id uuid,p_permission_key text
) returns json language sql stable security definer set search_path=''
as $$
select json_build_object('allowed',exists(
  select 1 from public.admins a
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where a.user_id=p_user_id and p.key=p_permission_key
));
$$;
revoke execute on function public.mc_get_staff_permission(uuid,text) from public;
grant execute on function public.mc_get_staff_permission(uuid,text) to service_role;
