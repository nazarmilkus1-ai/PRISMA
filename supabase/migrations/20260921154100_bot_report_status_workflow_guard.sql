-- Guard report status transitions and record report history.
create or replace function public.bot_set_report_status(
  p_report_id uuid,
  p_status text,
  p_admin_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
  admin_uuid uuid;
  permission_key text;
  old_status text;
  new_status text;
begin
  new_status := upper(trim(p_status));

  if new_status not in ('IN_REVIEW', 'RESOLVED', 'DISMISSED') then
    raise exception 'INVALID_REPORT_STATUS';
  end if;

  permission_key := case new_status
    when 'IN_REVIEW' then 'report.assign'
    when 'RESOLVED' then 'report.resolve'
    when 'DISMISSED' then 'report.reject'
  end;

  select a.id
    into admin_uuid
  from public.admins a
  join public.users u on u.id = a.user_id
  join public.role_permissions rp on rp.role_id = a.role_id
  join public.permissions p on p.id = rp.permission_id
  where u.telegram_id = p_admin_tg_id
    and p.key = permission_key
  limit 1;

  if admin_uuid is null then
    raise exception 'ADMIN_LACKS_PERMISSION';
  end if;

  select id, status::text, assigned_to
    into r
  from public.reports
  where id = p_report_id
  for update;

  if r.id is null then
    raise exception 'REPORT_NOT_FOUND';
  end if;

  old_status := upper(r.status);

  if old_status not in ('OPEN', 'IN_REVIEW') then
    raise exception 'REPORT_ALREADY_CLOSED';
  end if;

  if new_status = 'IN_REVIEW' and old_status = 'IN_REVIEW' then
    return json_build_object(
      'success', true,
      'report_id', r.id,
      'status', old_status,
      'duplicate', true
    );
  end if;

  update public.reports
  set status = new_status::public.report_status,
      assigned_to = case
        when new_status = 'IN_REVIEW' then admin_uuid
        else assigned_to
      end,
      resolved_at = case
        when new_status in ('RESOLVED', 'DISMISSED') then now()
        else null
      end,
      updated_at = now()
  where id = r.id;

  insert into public.report_history(
    report_id,
    actor_admin_id,
    from_status,
    to_status,
    from_assignee,
    to_assignee
  )
  values(
    r.id,
    admin_uuid,
    old_status,
    new_status,
    r.assigned_to,
    case when new_status = 'IN_REVIEW' then admin_uuid else r.assigned_to end
  );

  return json_build_object(
    'success', true,
    'report_id', r.id,
    'status', new_status,
    'duplicate', false
  );
end;
$function$;

revoke execute on function public.bot_set_report_status(uuid, text, bigint) from public, anon, authenticated;
grant execute on function public.bot_set_report_status(uuid, text, bigint) to service_role;
