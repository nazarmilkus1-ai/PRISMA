-- PRISMA v2: keep monitoring available to the moderator role after least-privilege tightening.

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key='system.health'
where r.name='moderator'
on conflict do nothing;
