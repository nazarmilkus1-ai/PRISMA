-- PRISMA v2: canonical recursive RBAC context for the authenticated panel.

create or replace function private.prisma_has_user_permission(
  p_user_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  with recursive role_chain as (
    select a.role_id, 1 as depth, array[a.role_id] as path
    from public.admins a
    join public.users u on u.id=a.user_id
    where a.user_id=p_user_id
      and u.deleted_at is null

    union all

    select r.parent_role_id, rc.depth + 1, rc.path || r.parent_role_id
    from role_chain rc
    join public.roles r on r.id=rc.role_id
    where r.parent_role_id is not null
      and not (r.parent_role_id = any(rc.path))
      and rc.depth < 20
  )
  select exists(
    select 1
    from role_chain rc
    join public.role_permissions rp on rp.role_id=rc.role_id
    join public.permissions p on p.id=rp.permission_id
    where p.key=p_permission_key
  );
$function$;

revoke all on function private.prisma_has_user_permission(uuid,text)
from public,anon,authenticated;

create or replace function public.staff_get_auth_context()
returns json
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor public.users%rowtype;
  admin_row public.admins%rowtype;
  role_row public.roles%rowtype;
  permissions_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.*
  into actor
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
  limit 1;

  if actor.id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;

  select a.*
  into admin_row
  from public.admins a
  where a.user_id=actor.id
  limit 1;

  if admin_row.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  select r.*
  into role_row
  from public.roles r
  where r.id=admin_row.role_id
  limit 1;

  if role_row.id is null then raise exception 'ROLE_NOT_FOUND'; end if;

  select coalesce(json_agg(distinct p.key order by p.key),'[]'::json)
  into permissions_data
  from (
    with recursive role_chain as (
      select a.role_id, 1 as depth, array[a.role_id] as path
      from public.admins a
      where a.id=admin_row.id

      union all

      select r.parent_role_id, rc.depth+1, rc.path||r.parent_role_id
      from role_chain rc
      join public.roles r on r.id=rc.role_id
      where r.parent_role_id is not null
        and not (r.parent_role_id = any(rc.path))
        and rc.depth < 20
    )
    select p.key
    from role_chain rc
    join public.role_permissions rp on rp.role_id=rc.role_id
    join public.permissions p on p.id=rp.permission_id
  ) p;

  return json_build_object(
    'user_id',actor.id,
    'admin_id',admin_row.id,
    'role',role_row.name,
    'role_id',role_row.id,
    'telegram_id',actor.telegram_id,
    'minecraft_nickname',actor.minecraft_nickname,
    'permissions',permissions_data
  );
end;
$function$;

revoke all on function public.staff_get_auth_context()
from public,anon;

grant execute on function public.staff_get_auth_context()
to authenticated;
