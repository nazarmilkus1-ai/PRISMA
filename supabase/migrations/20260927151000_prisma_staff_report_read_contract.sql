-- PRISMA v2: authenticated staff read contracts for reports.

create or replace function public.staff_list_reports(
  p_status text default 'OPEN',
  p_limit integer default 200
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  filter_status text := upper(trim(coalesce(p_status,'OPEN')));
  lim integer := greatest(1, least(coalesce(p_limit,200),500));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='report.view'
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  if filter_status not in ('ALL','OPEN','IN_REVIEW','RESOLVED','DISMISSED') then raise exception 'INVALID_STATUS'; end if;

  return coalesce((
    select json_agg(report_row order by created_sort desc)
    from (
      select json_build_object(
        'id',r.id,'ticket_no',r.ticket_no,'type',r.type,'target_nickname',r.target_nickname,
        'description',r.description,'status',r.status,'created_at',r.created_at,'user_id',r.user_id,
        'priority',r.priority,'category',r.category,
        'users',case when u.id is null then null else json_build_object(
          'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,'minecraft_nickname',u.minecraft_nickname
        ) end
      ) as report_row, r.created_at as created_sort
      from public.reports r
      left join public.users u on u.id=r.user_id
      where filter_status='ALL' or r.status::text=filter_status
      order by r.created_at desc
      limit lim
    ) rows_data
  ), '[]'::json);
end;
$function$;

revoke all on function public.staff_list_reports(text,integer) from public,anon;
grant execute on function public.staff_list_reports(text,integer) to authenticated;

create or replace function public.staff_get_report(p_report_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  report_data json;
  history_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='report.view'
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select json_build_object(
    'id',r.id,'ticket_no',r.ticket_no,'type',r.type,'target_nickname',r.target_nickname,
    'description',r.description,'status',r.status,'created_at',r.created_at,'updated_at',r.updated_at,
    'priority',r.priority,'category',r.category,'assigned_to',r.assigned_to,'evidence',r.evidence,
    'involved_players',r.involved_players,'coordinates',r.coordinates,'occurred_at',r.occurred_at,
    'resolved_at',r.resolved_at,'internal_notes',r.internal_notes,'sla_due_at',r.sla_due_at,
    'source_type',r.source_type,'source_id',r.source_id,'user_id',r.user_id,
    'users',case when u.id is null then null else json_build_object(
      'id',u.id,'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,
      'minecraft_nickname',u.minecraft_nickname,'full_name',u.full_name
    ) end
  ) into report_data
  from public.reports r
  left join public.users u on u.id=r.user_id
  where r.id=p_report_id;

  if report_data is null then raise exception 'REPORT_NOT_FOUND'; end if;

  select coalesce(json_agg(
    json_build_object(
      'id',h.id,'from_status',h.from_status,'to_status',h.to_status,
      'from_assignee',h.from_assignee,'to_assignee',h.to_assignee,
      'note',h.note,'created_at',h.created_at
    ) order by h.created_at desc
  ),'[]'::json)
  into history_data
  from public.report_history h
  where h.report_id=p_report_id;

  return report_data::jsonb || jsonb_build_object('history',history_data)::jsonb;
end;
$function$;

revoke all on function public.staff_get_report(uuid) from public,anon;
grant execute on function public.staff_get_report(uuid) to authenticated;

create or replace function public.staff_report_stats()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  result json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='report.view'
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select json_build_object(
    'open',count(*) filter (where status='OPEN'),
    'in_review',count(*) filter (where status='IN_REVIEW'),
    'resolved',count(*) filter (where status='RESOLVED'),
    'dismissed',count(*) filter (where status='DISMISSED'),
    'total',count(*)
  ) into result from public.reports;
  return result;
end;
$function$;

revoke all on function public.staff_report_stats() from public,anon;
grant execute on function public.staff_report_stats() to authenticated;
