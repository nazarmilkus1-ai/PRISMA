-- PRISMA v2: preserve the live notification limit semantics in repository migrations.
create or replace function public.staff_list_notifications(p_limit integer default 200)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  lim integer := greatest(1, least(coalesce(p_limit,200),500));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and p.key='admin.view_audit'
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  return coalesce((
    select json_agg(json_build_object(
      'id',n.id,
      'telegram_id',n.telegram_id,
      'channel',n.channel,
      'kind',n.kind,
      'title',n.title,
      'body',n.body,
      'data',n.data,
      'status',n.status,
      'attempts',n.attempts,
      'last_error',n.last_error,
      'created_at',n.created_at,
      'sent_at',n.sent_at,
      'updated_at',n.updated_at
    ) order by n.created_at desc)
    from (
      select *
      from public.notifications
      order by created_at desc
      limit lim
    ) n
  ),'[]'::json);
end;
$function$;

revoke all on function public.staff_list_notifications(integer) from public,anon;
grant execute on function public.staff_list_notifications(integer) to authenticated;
