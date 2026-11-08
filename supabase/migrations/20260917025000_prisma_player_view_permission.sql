-- Permission used by the player roster API/page.
insert into public.permissions(key, description, category)
values ('player.view', 'Просмотр списка игроков', 'players')
on conflict (key) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where p.key = 'player.view'
  and r.name in ('owner', 'head_admin', 'admin', 'moderator')
on conflict do nothing;
