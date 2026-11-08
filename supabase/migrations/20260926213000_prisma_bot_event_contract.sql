create or replace function public.bot_list_events(p_tg_id bigint,p_limit integer default 20)
returns json
language plpgsql security definer set search_path='public'
as $function$
declare
  uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null
  limit 1;
  if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;

  return coalesce((
    select json_agg(x order by x.starts_at asc nulls last)
    from (
      select
        e.id,e.slug,e.title,e.description,e.status,e.starts_at,e.ends_at,
        e.registration_deadline,e.max_participants,e.reward_config,
        exists(
          select 1 from public.event_participants ep
          where ep.event_id=e.id and ep.user_id=uid
        ) as registered,
        (
          select count(*)::integer
          from public.event_participants ep
          where ep.event_id=e.id
        ) as participant_count
      from public.events e
      where e.status in ('scheduled','live')
      order by e.starts_at asc nulls last
      limit greatest(1,least(coalesce(p_limit,20),50))
    ) x
  ),'[]'::json);
end;
$function$;

create or replace function public.bot_register_event(p_tg_id bigint,p_event_id uuid)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_register_event(uid,p_event_id);
end;
$function$;

create or replace function public.bot_unregister_event(p_tg_id bigint,p_event_id uuid)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_unregister_event(uid,p_event_id);
end;
$function$;

revoke execute on function public.bot_list_events(bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_list_events(bigint,integer) to service_role;
revoke execute on function public.bot_register_event(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_register_event(bigint,uuid) to service_role;
revoke execute on function public.bot_unregister_event(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_unregister_event(bigint,uuid) to service_role;