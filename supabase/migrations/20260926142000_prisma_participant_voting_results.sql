create or replace function private.prisma_participant_get_voting(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        p.id,
        p.question,
        p.description,
        p.kind,
        p.kind_text,
        p.expires_at,
        p.status,
        p.visibility,
        p.allow_multiple,
        p.max_choices,
        p.allow_change_vote,
        p.created_at,
        exists(select 1 from public.admins a where a.user_id=p.created_by) as admin_created,
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id',o.id,
              'text',o.text,
              'position',o.position,
              'vote_count',coalesce((select count(*) from public.poll_votes v where v.option_id=o.id),0),
              'selected',exists(
                select 1 from public.poll_votes v
                where v.poll_id=p.id and v.option_id=o.id and v.user_id=p_user_id
              )
            )
            order by o.position
          )
          from public.poll_options o
          where o.poll_id=p.id
        ),'[]'::jsonb) as options,
        coalesce((
          select count(*) from public.poll_votes v where v.poll_id=p.id
        ),0) as total_votes,
        exists(
          select 1 from public.poll_votes v
          where v.poll_id=p.id and v.user_id=p_user_id
        ) as voted
      from public.polls p
      where p.visibility='public'
        and p.status='active'
        and (p.expires_at is null or p.expires_at>now())
      order by p.created_at desc
      limit 100
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_get_voting()
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
  return private.prisma_participant_get_voting(uid);
end;
$function$;

revoke all on function public.participant_get_voting() from public,anon;
grant execute on function public.participant_get_voting() to authenticated;

create index if not exists poll_votes_poll_option_idx on public.poll_votes(poll_id,option_id);