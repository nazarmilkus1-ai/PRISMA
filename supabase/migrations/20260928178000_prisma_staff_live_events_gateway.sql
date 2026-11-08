-- PRISMA v2: canonical staff gateway for Minecraft live events.
create or replace function public.staff_get_live_events(p_limit integer default 100)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  lim integer := greatest(1, least(coalesce(p_limit, 100), 200));
begin
  if actor_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select u.id
    into actor_id
  from public.users u
  join public.admins a on a.user_id = u.id
  join public.role_permissions rp on rp.role_id = a.role_id
  join public.permissions p on p.id = rp.permission_id
  where u.auth_user_id = actor_uid
    and u.deleted_at is null
    and p.key = 'system.health'
  limit 1;

  if actor_id is null then
    raise exception 'PERMISSION_DENIED';
  end if;

  return coalesce(
    (
      select json_agg(row_data order by row_data->>'created_at' desc)
      from (
        select json_build_object(
          'id', e.id,
          'event_type', e.event_type,
          'nickname', e.nickname,
          'command', e.command,
          'message', e.message,
          'world', e.world,
          'created_at', e.created_at
        ) as row_data
        from public.minecraft_events e
        order by e.created_at desc
        limit lim
      ) rows_data
    ),
    '[]'::json
  );
end;
$function$;

revoke execute on function public.staff_get_live_events(integer) from public, anon;
grant execute on function public.staff_get_live_events(integer) to authenticated;
grant execute on function public.staff_get_live_events(integer) to postgres;
