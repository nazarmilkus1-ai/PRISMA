-- Event detail gateway exposes registration state without exposing participant identity.

create or replace function public.get_public_event_details(p_slug text)
returns jsonb
language sql security definer set search_path=''
as $function$
  select (
    select jsonb_build_object(
      'event',jsonb_build_object(
        'id',e.id,'slug',e.slug,'title',e.title,'description',e.description,'status',e.status,
        'starts_at',e.starts_at,'ends_at',e.ends_at,'registration_deadline',e.registration_deadline,
        'max_participants',e.max_participants,'reward_config',e.reward_config,'created_at',e.created_at,
        'registration_open',(
          e.status in ('scheduled','live','published','registration','open','active')
          and (e.registration_deadline is null or e.registration_deadline>now())
        ),
        'registered',case
          when (select auth.uid()) is null then false
          else exists(
            select 1
            from public.event_participants ep
            join public.users au on au.id=ep.user_id
            where ep.event_id=e.id and au.auth_user_id=(select auth.uid())
          )
        end
      ),
      'participants',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'minecraft_nickname',u.minecraft_nickname,'score',ep.score,'placement',ep.placement
          )
          order by ep.placement asc nulls last,ep.score desc
        )
        from public.event_participants ep
        join public.users u on u.id=ep.user_id
        where ep.event_id=e.id and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
      ),'[]'::jsonb)
    )
    from public.events e
    where e.slug=trim(p_slug) and e.status<>'draft'
    limit 1
  );
$function$;
