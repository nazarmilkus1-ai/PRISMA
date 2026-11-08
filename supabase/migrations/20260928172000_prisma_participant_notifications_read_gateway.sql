-- PRISMA v2: canonical authenticated notification read gateway.
-- The caller can only read notifications belonging to auth.uid()-linked user.
create or replace function public.participant_get_notifications(p_limit integer default 100)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(jsonb_agg(
  jsonb_build_object(
    'id', n.id,
    'kind', n.kind,
    'title', n.title,
    'body', n.body,
    'data', n.data,
    'status', n.status,
    'created_at', n.created_at,
    'updated_at', n.updated_at
  )
  order by n.created_at desc
), '[]'::jsonb)
from (
  select n.id,n.kind,n.title,n.body,n.data,n.status,n.created_at,n.updated_at
  from public.notifications n
  where n.user_id = (
    select u.id
    from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.deleted_at is null
    limit 1
  )
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 100)
) n;
$function$;

revoke execute on function public.participant_get_notifications(integer) from public, anon;
grant execute on function public.participant_get_notifications(integer) to authenticated;
grant execute on function public.participant_get_notifications(integer) to postgres;
