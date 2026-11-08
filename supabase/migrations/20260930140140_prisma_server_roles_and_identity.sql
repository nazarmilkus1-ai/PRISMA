create or replace function public.mc_get_staff_identity(p_user_id uuid)
returns json
language sql
stable
security definer
set search_path = ''
as $$
  select json_build_object(
    'rank',
      case coalesce(r.name, 'participant')
        when 'helper' then 1
        when 'moderator' then 2
        when 'admin' then 3
        when 'head_admin' then 4
        when 'owner' then 5
        else 0
      end,
    'role',
      coalesce(r.name, 'participant'),
    'priority',
      coalesce(r.priority, 0)
  )
  from (select p_user_id as user_id) input
  left join public.admins a on a.user_id = input.user_id
  left join public.roles r on r.id = a.role_id;
$$;

revoke execute on function public.mc_get_staff_identity(uuid) from public, anon, authenticated;
grant execute on function public.mc_get_staff_identity(uuid) to service_role;

create or replace function public.participant_get_server_role()
returns json
language sql
stable
security definer
set search_path = ''
as $$
  select json_build_object(
    'rank',
      case coalesce(r.name, 'participant')
        when 'helper' then 1
        when 'moderator' then 2
        when 'admin' then 3
        when 'head_admin' then 4
        when 'owner' then 5
        else 0
      end,
    'role',
      coalesce(r.name, 'participant'),
    'priority',
      coalesce(r.priority, 0)
  )
  from public.users u
  left join public.admins a on a.user_id = u.id
  left join public.roles r on r.id = a.role_id
  where u.auth_user_id = auth.uid()
    and u.deleted_at is null
  limit 1;
$$;

revoke execute on function public.participant_get_server_role() from public, anon;
grant execute on function public.participant_get_server_role() to authenticated;
