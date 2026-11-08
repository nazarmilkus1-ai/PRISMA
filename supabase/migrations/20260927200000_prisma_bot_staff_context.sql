-- PRISMA v2: one trusted bot staff-context lookup.
-- Avoid repeated bot_check_admin_permission calls when resolving staff mode.

create or replace function public.bot_get_staff_context(p_tg_id bigint)
returns json
language sql
stable
security definer
set search_path=''
as $function$
with recursive role_chain as (
  select a.role_id, 1 as depth, array[a.role_id] as path
  from public.admins a
  join public.users u on u.id=a.user_id
  where u.telegram_id=p_tg_id
    and u.deleted_at is null

  union all

  select r.parent_role_id, rc.depth+1, rc.path||r.parent_role_id
  from role_chain rc
  join public.roles r on r.id=rc.role_id
  where r.parent_role_id is not null
    and not (r.parent_role_id=any(rc.path))
    and rc.depth<20
)
select json_build_object(
  'is_staff',exists(select 1 from role_chain),
  'role',(
    select json_build_object('name',r.name,'priority',r.priority)
    from public.admins a
    join public.roles r on r.id=a.role_id
    join public.users u on u.id=a.user_id
    where u.telegram_id=p_tg_id
      and u.deleted_at is null
    limit 1
  ),
  'permissions',coalesce((
    select json_agg(distinct p.key order by p.key)
    from role_chain rc
    join public.role_permissions rp on rp.role_id=rc.role_id
    join public.permissions p on p.id=rp.permission_id
  ),'[]'::json)
);
$function$;

revoke all on function public.bot_get_staff_context(bigint) from public,anon,authenticated;
grant execute on function public.bot_get_staff_context(bigint) to service_role;
