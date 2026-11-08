-- PRISMA 2.0.0: canonical staff read gateway for map history.
insert into public.permissions(key,description,category)
values ('map.history.view','Просмотр истории карты','map')
on conflict (key) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key='map.history.view'
where r.name in ('owner','head_admin','admin','moderator')
on conflict do nothing;

create or replace function public.staff_get_map_history(
  p_limit integer default 100
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id
      and p.key='map.history.view'
  ) then
    raise exception 'PERMISSION_DENIED';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        mh.id,
        mh.marker_id,
        mh.action,
        mh.snapshot,
        mh.created_by,
        mh.created_at
      from public.map_history mh
      order by mh.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),100))
    ) x
  ),'[]'::jsonb);
end;
$function$;

revoke all on function public.staff_get_map_history(integer) from public,anon;
grant execute on function public.staff_get_map_history(integer) to authenticated;
