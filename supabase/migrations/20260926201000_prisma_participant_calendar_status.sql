create or replace function private.prisma_participant_get_calendar(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);

  return coalesce((
    select jsonb_agg(
      to_jsonb(x) order by x.starts_at asc nulls last
    )
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
        ) as my_result,
        (
          select count(*)::integer
          from public.event_participants ep
          where ep.event_id=e.id
        ) as participant_count
      from public.events e
      where e.status in ('published','scheduled','live','finished')
      order by e.starts_at asc nulls last
      limit 200
    ) x
  ),'[]'::jsonb);
end;
$function$;