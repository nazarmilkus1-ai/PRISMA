-- PRISMA v2: current-admin auth security read gateway.
-- Login history and profile data stay behind the authenticated staff boundary.

create or replace function public.staff_get_auth_security()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor public.users%rowtype;
  admin_row public.admins%rowtype;
  role_row public.roles%rowtype;
  profile_data json;
  history_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.* into actor
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
  limit 1;
  if actor.id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;

  select a.* into admin_row from public.admins a where a.user_id=actor.id limit 1;
  if admin_row.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;

  select r.* into role_row from public.roles r where r.id=admin_row.role_id limit 1;

  select json_build_object(
    'id',actor.id,'telegram_id',actor.telegram_id,'telegram_username',actor.telegram_username,
    'first_name',actor.first_name,'last_name',actor.last_name,'full_name',actor.full_name,
    'status',actor.status,'rating',actor.rating,'activity_score',actor.activity_score,
    'last_seen_at',actor.last_seen_at,'created_at',actor.created_at,
    'minecraft_nickname',actor.minecraft_nickname,'platform',actor.platform
  ) into profile_data;

  select coalesce(json_agg(json_build_object(
    'id',lh.id,'method',lh.method,'success',lh.success,'ip_hash',lh.ip_hash,
    'user_agent',lh.user_agent,'created_at',lh.created_at
  ) order by lh.created_at desc),'[]'::json)
  into history_data
  from (
    select * from public.login_history
    where auth_user_id=actor_uid
    order by created_at desc
    limit 50
  ) lh;

  return json_build_object('profile',profile_data,'role',role_row.name,'login_history',history_data);
end;
$function$;

revoke all on function public.staff_get_auth_security() from public,anon;
grant execute on function public.staff_get_auth_security() to authenticated;
