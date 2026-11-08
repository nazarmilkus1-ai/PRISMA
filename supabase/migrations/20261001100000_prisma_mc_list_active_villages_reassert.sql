create or replace function public.mc_list_active_villages()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  select json_build_object(
    'villages',
    coalesce(
      json_agg(
        json_build_object(
          'id', cv.id,
          'clan_id', cv.clan_id,
          'name', cv.name,
          'world', cv.world,
          'center_x', cv.center_x,
          'center_y', cv.center_y,
          'center_z', cv.center_z,
          'radius', cv.radius
        )
        order by cv.created_at
      ),
      '[]'::json
    )
  )
  from public.clan_villages cv
  where cv.status = 'active';
$$;

revoke all on function public.mc_list_active_villages() from public, anon, authenticated;
grant execute on function public.mc_list_active_villages() to service_role;
