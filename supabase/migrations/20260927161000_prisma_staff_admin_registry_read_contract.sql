-- PRISMA v2: authenticated staff read gateway for admin registry.

create or replace function public.staff_get_admin_registry()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  admins_data json;
  roles_data json;
  role_permissions_data json;
  permissions_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and p.key='admin.view_audit'
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select coalesce(json_agg(x order by x->>'created_at'),'[]'::json)
  into admins_data
  from (
    select json_build_object(
      'id',a.id,'user_id',a.user_id,'role_id',a.role_id,'created_at',a.created_at,
      'users',json_build_object(
        'id',u.id,'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,
        'first_name',u.first_name,'full_name',u.full_name,'minecraft_nickname',u.minecraft_nickname,
        'status',u.status,'is_whitelisted',u.is_whitelisted,'is_banned',u.is_banned,
        'is_muted',u.is_muted,'rating',u.rating,'activity_score',u.activity_score,'last_seen_at',u.last_seen_at
      ),
      'roles',json_build_object(
        'id',r.id,'name',r.name,'description',r.description,'priority',r.priority
      )
    ) as x
    from public.admins a
    join public.users u on u.id=a.user_id and u.deleted_at is null
    join public.roles r on r.id=a.role_id
  ) rows_data;

  select coalesce(json_agg(to_jsonb(r) order by r.priority desc, r.name),'[]'::json) into roles_data from public.roles r;
  select coalesce(json_agg(to_jsonb(rp) order by rp.role_id, rp.permission_id),'[]'::json) into role_permissions_data from public.role_permissions rp;
  select coalesce(json_agg(to_jsonb(p) order by p.category, p.key),'[]'::json) into permissions_data from public.permissions p;

  return json_build_object('admins',admins_data,'roles',roles_data,'role_permissions',role_permissions_data,'permissions',permissions_data);
end;
$function$;

revoke all on function public.staff_get_admin_registry() from public,anon;
grant execute on function public.staff_get_admin_registry() to authenticated;
