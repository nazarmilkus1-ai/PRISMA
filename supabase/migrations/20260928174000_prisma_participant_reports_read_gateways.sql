-- PRISMA v2: canonical authenticated report read gateways.
-- All report reads are scoped to the participant resolved from auth.uid().

create or replace function public.participant_get_reports(p_limit integer default 50)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(jsonb_agg(
  jsonb_build_object(
    'id', r.id,
    'ticket_no', r.ticket_no,
    'type', r.type,
    'target_nickname', r.target_nickname,
    'description', r.description,
    'status', r.status,
    'priority', r.priority,
    'category', r.category,
    'created_at', r.created_at,
    'updated_at', r.updated_at,
    'resolved_at', r.resolved_at
  )
  order by r.created_at desc
), '[]'::jsonb)
from (
  select
    r.id,
    r.ticket_no,
    r.type,
    r.target_nickname,
    r.description,
    r.status,
    r.priority,
    r.category,
    r.created_at,
    r.updated_at,
    r.resolved_at
  from public.reports r
  where r.user_id = (
    select u.id
    from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.deleted_at is null
    limit 1
  )
  order by r.created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
) r;
$function$;

create or replace function public.participant_get_report(p_report_id uuid)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(
  (
    select jsonb_build_object(
      'report', jsonb_build_object(
        'id', r.id,
        'ticket_no', r.ticket_no,
        'type', r.type,
        'target_nickname', r.target_nickname,
        'description', r.description,
        'status', r.status,
        'priority', r.priority,
        'category', r.category,
        'created_at', r.created_at,
        'updated_at', r.updated_at,
        'resolved_at', r.resolved_at,
        'occurred_at', r.occurred_at
      ),
      'history', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', h.id,
            'from_status', h.from_status,
            'to_status', h.to_status,
            'created_at', h.created_at
          )
          order by h.created_at asc
        )
        from public.report_history h
        where h.report_id = r.id
      ), '[]'::jsonb)
    )
    from public.reports r
    where r.id = p_report_id
      and r.user_id = (
        select u.id
        from public.users u
        where u.auth_user_id = (select auth.uid())
          and u.deleted_at is null
        limit 1
      )
    limit 1
  ),
  null
);
$function$;

revoke execute on function public.participant_get_reports(integer) from public, anon;
revoke execute on function public.participant_get_report(uuid) from public, anon;
grant execute on function public.participant_get_reports(integer) to authenticated;
grant execute on function public.participant_get_report(uuid) to authenticated;
grant execute on function public.participant_get_reports(integer) to postgres;
grant execute on function public.participant_get_report(uuid) to postgres;
