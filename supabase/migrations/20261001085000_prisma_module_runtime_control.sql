create table if not exists public.prisma_module_states (
  module_id text primary key check (module_id ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  enabled boolean not null default true,
  reason text check (reason is null or char_length(trim(reason)) between 0 and 500),
  updated_by uuid references public.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.prisma_module_states enable row level security;
revoke all on table public.prisma_module_states from public, anon, authenticated;

create index if not exists prisma_module_states_updated_idx
  on public.prisma_module_states(updated_at desc);

insert into public.prisma_module_states(module_id, enabled)
values
  ('auth', true),
  ('applications', true),
  ('players', true),
  ('battles', true),
  ('moderation', true),
  ('reports', true),
  ('appeals', true),
  ('clans', true),
  ('events', true),
  ('market', true),
  ('voting', true),
  ('notifications', true),
  ('social', true),
  ('map', true),
  ('chat', true),
  ('analytics', true),
  ('audit-security', true),
  ('minecraft', true),
  ('public-content', true),
  ('staff-core', true)
on conflict (module_id) do nothing;

create or replace function public.get_public_module_state(p_module_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'module_id', p_module_id,
    'enabled', coalesce(
      (select s.enabled
       from public.prisma_module_states s
       where s.module_id = lower(trim(p_module_id))),
      true
    )
  );
$$;

create or replace function public.get_public_module_states()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'module_id', s.module_id,
        'enabled', s.enabled
      )
      order by s.module_id
    ),
    '[]'::jsonb
  )
  from public.prisma_module_states s;
$$;

create or replace function public.staff_get_module_states()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
begin
  if actor_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select u.id
    into actor_id
  from public.users u
  where u.auth_user_id = actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id, 'modules.view')
  limit 1;

  if actor_id is null then
    raise exception 'PERMISSION_DENIED';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'module_id', s.module_id,
        'enabled', s.enabled,
        'reason', s.reason,
        'updated_by', s.updated_by,
        'updated_at', s.updated_at
      )
      order by s.module_id
    )
    from public.prisma_module_states s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.staff_set_module_state(
  p_module_id text,
  p_enabled boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  normalized_id text := lower(trim(p_module_id));
  old_row public.prisma_module_states%rowtype;
  new_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if actor_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if normalized_id !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'INVALID_MODULE_ID';
  end if;

  if p_enabled is null then
    raise exception 'INVALID_ENABLED';
  end if;

  if new_reason is not null and char_length(new_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  select u.id
    into actor_id
  from public.users u
  where u.auth_user_id = actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id, 'modules.manage')
  limit 1;

  if actor_id is null then
    raise exception 'PERMISSION_DENIED';
  end if;

  select *
    into old_row
  from public.prisma_module_states
  where module_id = normalized_id
  for update;

  insert into public.prisma_module_states(module_id, enabled, reason, updated_by, updated_at)
  values (normalized_id, p_enabled, new_reason, actor_id, now())
  on conflict (module_id) do update
    set enabled = excluded.enabled,
        reason = excluded.reason,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  insert into public.audit_logs(
    actor_user_id,
    actor_tg_id,
    action,
    target_type,
    target_id,
    old_data,
    new_data
  )
  values (
    actor_id,
    (select u.telegram_id from public.users u where u.id = actor_id),
    case when p_enabled then 'module.enable' else 'module.disable' end,
    'module',
    normalized_id,
    case when old_row.module_id is null then null else to_jsonb(old_row) end,
    jsonb_build_object(
      'module_id', normalized_id,
      'enabled', p_enabled,
      'reason', new_reason
    )
  );

  return jsonb_build_object(
    'success', true,
    'module_id', normalized_id,
    'enabled', p_enabled,
    'reason', new_reason
  );
end;
$$;

insert into public.permissions(key, description)
values
  ('modules.view', 'Просмотр состояния модулей'),
  ('modules.manage', 'Управление состоянием модулей')
on conflict (key) do update set description = excluded.description;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.name in ('owner', 'head_admin', 'admin')
  and p.key in ('modules.view', 'modules.manage')
on conflict do nothing;

revoke all on function public.get_public_module_state(text) from public, anon, authenticated, service_role;
revoke all on function public.get_public_module_states() from public, anon, authenticated, service_role;
revoke all on function public.staff_get_module_states() from public, anon, authenticated, service_role;
revoke all on function public.staff_set_module_state(text, boolean, text) from public, anon, authenticated, service_role;

grant execute on function public.get_public_module_state(text) to anon, authenticated, service_role;
grant execute on function public.get_public_module_states() to anon, authenticated, service_role;
grant execute on function public.staff_get_module_states() to authenticated, service_role;
grant execute on function public.staff_set_module_state(text, boolean, text) to authenticated, service_role;
