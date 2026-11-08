-- PRISMA 2.0.0: staff read-only Minecraft auth status.
-- Password hashes are never returned to staff clients.

create or replace function public.staff_get_minecraft_auth_status(
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
begin
  if actor_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and p.key='player.view'
  limit 1;

  if actor_id is null then
    raise exception 'PERMISSION_DENIED';
  end if;

  return coalesce((
    select jsonb_build_object(
      'configured',exists(
        select 1 from public.minecraft_auth_credentials c where c.user_id=u.id
      ),
      'last_login_at',(
        select c.last_login_at
        from public.minecraft_auth_credentials c
        where c.user_id=u.id
      ),
      'locked_until',(
        select c.locked_until
        from public.minecraft_auth_credentials c
        where c.user_id=u.id
      )
    )
    from public.users u
    where u.id=p_user_id and u.deleted_at is null
  ), jsonb_build_object('error','PLAYER_NOT_FOUND'));
end;
$function$;

revoke all on function public.staff_get_minecraft_auth_status(uuid) from public,anon;
grant execute on function public.staff_get_minecraft_auth_status(uuid) to authenticated;
