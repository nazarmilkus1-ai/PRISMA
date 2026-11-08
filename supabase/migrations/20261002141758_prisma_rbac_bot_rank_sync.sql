-- PRISMA RBAC: align bot staff listing and numeric promotion with the new hierarchy.
create or replace function public.bot_list_staff()
returns json
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(json_agg(x order by x.priority desc,x.full_name),'[]'::json)
  from (
    select
      u.telegram_id as tg_id,
      u.full_name,
      u.telegram_username,
      r.name as role,
      r.priority,
      r.branch,
      r.rank_label,
      case r.name
        when 'helper' then 0.5
        when 'moderator' then 1
        when 'senior_moderator' then 2
        when 'admin' then 3
        when 'head_staff' then 3.5
        when 'head_admin' then 4
        when 'owner' then 5
        else 0
      end as rank
    from public.admins a
    join public.users u on u.id=a.user_id
    join public.roles r on r.id=a.role_id
    where u.deleted_at is null
  ) x;
$$;

revoke execute on function public.bot_list_staff() from public,anon,authenticated;
grant execute on function public.bot_list_staff() to service_role;
