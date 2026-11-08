-- PRISMA v2: canonical participant notification-preference read gateway.
create or replace function public.participant_get_notification_preferences()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(
  (
    select jsonb_build_object(
      'news', p.news,
      'events', p.events,
      'server_status', p.server_status,
      'clan_news', p.clan_news,
      'moderation', p.moderation,
      'polls', p.polls,
      'social', p.social,
      'battles', p.battles,
      'market', p.market
    )
    from public.notification_preferences p
    where p.user_id = (
      select u.id
      from public.users u
      where u.auth_user_id = (select auth.uid())
        and u.deleted_at is null
      limit 1
    )
    limit 1
  ),
  jsonb_build_object(
    'news', true,
    'events', true,
    'server_status', true,
    'clan_news', true,
    'moderation', true,
    'polls', true,
    'social', true,
    'battles', true,
    'market', true
  )
);
$function$;

revoke execute on function public.participant_get_notification_preferences() from public, anon;
grant execute on function public.participant_get_notification_preferences() to authenticated;
grant execute on function public.participant_get_notification_preferences() to postgres;
