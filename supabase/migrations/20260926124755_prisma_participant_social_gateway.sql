CREATE OR REPLACE FUNCTION private.prisma_participant_get_social(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  result jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select jsonb_build_object(
    'marriage', coalesce((
      select jsonb_build_object(
        'id',m.id,
        'partner_id',p.id,
        'partner_nickname',p.minecraft_nickname,
        'married_at',m.married_at,
        'source',m.source
      )
      from public.marriages m
      join public.users p on p.id=case when m.user_a_id=p_user_id then m.user_b_id else m.user_a_id end
      where m.status='ACTIVE'
        and (m.user_a_id=p_user_id or m.user_b_id=p_user_id)
        and p.deleted_at is null
      order by m.married_at desc
      limit 1
    ), 'null'::jsonb),
    'relationship', coalesce((
      select jsonb_build_object(
        'id',r.id,
        'partner_id',p.id,
        'partner_nickname',p.minecraft_nickname,
        'started_at',r.started_at
      )
      from public.relationships r
      join public.users p on p.id=case when r.user_a_id=p_user_id then r.user_b_id else r.user_a_id end
      where r.status='ACTIVE'
        and (r.user_a_id=p_user_id or r.user_b_id=p_user_id)
        and p.deleted_at is null
      order by r.started_at desc
      limit 1
    ), 'null'::jsonb),
    'marriage_history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',h.id,
          'partner_nickname',p.minecraft_nickname,
          'status',h.status,
          'married_at',h.married_at,
          'divorced_at',h.divorced_at
        )
        order by h.married_at desc
      )
      from (
        select m.id,m.user_a_id,m.user_b_id,m.status,m.married_at,m.divorced_at
        from public.marriages m
        where (m.user_a_id=p_user_id or m.user_b_id=p_user_id)
        order by m.married_at desc
        limit 20
      ) h
      join public.users p on p.id=case when h.user_a_id=p_user_id then h.user_b_id else h.user_a_id end
      where p.deleted_at is null
    ), '[]'::jsonb),
    'relationship_history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',h.id,
          'partner_nickname',p.minecraft_nickname,
          'status',h.status,
          'started_at',h.started_at,
          'ended_at',h.ended_at
        )
        order by h.started_at desc
      )
      from (
        select r.id,r.user_a_id,r.user_b_id,r.status,r.started_at,r.ended_at
        from public.relationships r
        where (r.user_a_id=p_user_id or r.user_b_id=p_user_id)
        order by r.started_at desc
        limit 20
      ) h
      join public.users p on p.id=case when h.user_a_id=p_user_id then h.user_b_id else h.user_a_id end
      where p.deleted_at is null
    ), '[]'::jsonb),
    'marriage_requests_in', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',q.id,
          'requester_nickname',u.minecraft_nickname,
          'created_at',q.created_at
        )
        order by q.created_at desc
      )
      from (
        select id,requester_id,created_at
        from public.marriage_requests
        where target_id=p_user_id and status='pending'
        order by created_at desc
        limit 10
      ) q
      join public.users u on u.id=q.requester_id
      where u.deleted_at is null
    ), '[]'::jsonb),
    'relationship_requests_in', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',q.id,
          'requester_nickname',u.minecraft_nickname,
          'created_at',q.created_at
        )
        order by q.created_at desc
      )
      from (
        select id,requester_id,created_at
        from public.relationship_requests
        where target_id=p_user_id and status='pending'
        order by created_at desc
        limit 10
      ) q
      join public.users u on u.id=q.requester_id
      where u.deleted_at is null
    ), '[]'::jsonb)
  )
  into result;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_get_social()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_social(uid);
end;
$function$;

revoke all on function public.participant_get_social() from public;
grant execute on function public.participant_get_social() to authenticated;