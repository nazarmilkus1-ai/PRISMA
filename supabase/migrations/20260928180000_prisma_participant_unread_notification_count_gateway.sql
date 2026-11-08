-- PRISMA v2: canonical unread-notification count for the participant shell.
create or replace function public.participant_get_unread_notification_count()
returns integer
language sql
security definer
set search_path to ''
as $function$
select count(*)::integer
from public.notifications n
where n.user_id = (
  select u.id
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1
)
and n.status = 'sent';
$function$;

revoke execute on function public.participant_get_unread_notification_count() from public, anon;
grant execute on function public.participant_get_unread_notification_count() to authenticated;
grant execute on function public.participant_get_unread_notification_count() to postgres;
