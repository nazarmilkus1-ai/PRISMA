create policy "deny direct client access to module states"
  on public.prisma_module_states
  as restrictive
  for all
  to anon, authenticated
  using (false)
  with check (false);

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

  if not p_enabled and normalized_id in ('auth', 'staff-core') then
    raise exception 'PROTECTED_MODULE';
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

revoke all on function public.staff_set_module_state(text, boolean, text) from public, anon, authenticated, service_role;
grant execute on function public.staff_set_module_state(text, boolean, text) to authenticated, service_role;
