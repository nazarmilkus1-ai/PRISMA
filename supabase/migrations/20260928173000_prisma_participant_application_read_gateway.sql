-- PRISMA v2: canonical authenticated application read gateway.
-- A participant can only read their own latest application.
create or replace function public.participant_get_application()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(
  (
    select jsonb_build_object(
      'id', a.id,
      'application_no', a.application_no,
      'full_name', a.full_name,
      'age', a.age,
      'nickname', a.nickname,
      'platform', a.platform,
      'discovery_source', a.discovery_source,
      'status', a.status,
      'rejection_reason', a.rejection_reason,
      'created_at', a.created_at,
      'updated_at', a.updated_at,
      'reviewed_at', a.reviewed_at,
      'birth_date', a.birth_date,
      'goal', a.goal,
      'about', a.about,
      'cooldown_until', a.cooldown_until
    )
    from public.applications a
    where a.user_id = (
      select u.id
      from public.users u
      where u.auth_user_id = (select auth.uid())
        and u.deleted_at is null
      limit 1
    )
    order by a.created_at desc
    limit 1
  ),
  null
);
$function$;

revoke execute on function public.participant_get_application() from public, anon;
grant execute on function public.participant_get_application() to authenticated;
grant execute on function public.participant_get_application() to postgres;
