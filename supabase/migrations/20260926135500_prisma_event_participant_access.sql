drop policy if exists event_participants_read on public.event_participants;

create policy event_participants_read
on public.event_participants
for select
to authenticated
using (
  exists(
    select 1
    from public.users u
    where u.id=event_participants.user_id
      and u.auth_user_id=(select auth.uid())
      and u.deleted_at is null
  )
  or (select private.has_permission('event.manage'::text))
);

create or replace function private.prisma_participant_get_calendar(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.starts_at asc nulls last)
    from (
      select
        e.id,e.slug,e.title,e.description,e.status,e.starts_at,e.ends_at,
        e.registration_deadline,e.max_participants,e.reward_config,e.created_at,
        exists(
          select 1 from public.event_participants ep
          where ep.event_id=e.id and ep.user_id=p_user_id
        ) as registered,
        (
          select jsonb_build_object(
            'score',ep.score,
            'placement',ep.placement,
            'registered_at',ep.registered_at
          )
          from public.event_participants ep
          where ep.event_id=e.id and ep.user_id=p_user_id
          limit 1
        ) as my_result
      from public.events e
      where e.status in ('published','scheduled','live','finished')
      order by e.starts_at asc nulls last
      limit 100
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_get_calendar()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_calendar(uid);
end;
$function$;

revoke all on function public.participant_get_calendar() from public,anon;
grant execute on function public.participant_get_calendar() to authenticated;