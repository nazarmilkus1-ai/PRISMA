-- Correction for the first social v2 migration:
-- avoid PL/pgSQL variable/column name ambiguity by using v_target_id.

create or replace function private.prisma_bot_social_request(
  p_tg_id bigint,
  p_target_tg_id bigint,
  p_kind text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid;
  v_target_id uuid;
  request_id uuid;
  actor_name text;
  target_name text;
  kind text:=upper(trim(coalesce(p_kind,'')));
begin
  actor_id:=private.prisma_bot_social_require_user(p_tg_id);
  v_target_id:=private.prisma_bot_social_require_user(p_target_tg_id);

  if actor_id=v_target_id then
    raise exception 'SELF_TARGET_FORBIDDEN';
  end if;
  if kind not in ('MARRIAGE','RELATIONSHIP') then
    raise exception 'INVALID_SOCIAL_KIND';
  end if;

  perform 1
  from public.users u
  where u.id in (actor_id,v_target_id)
  order by u.id
  for update;

  select coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок')
    into actor_name
  from public.users u where u.id=actor_id;

  select coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок')
    into target_name
  from public.users u where u.id=v_target_id;

  if kind='MARRIAGE' then
    if exists(
      select 1 from public.marriages m
      where m.status='ACTIVE'
        and (m.user_a_id in (actor_id,v_target_id) or m.user_b_id in (actor_id,v_target_id))
    ) then
      raise exception 'ALREADY_MARRIED';
    end if;

    if exists(
      select 1 from public.marriage_requests q
      where q.requester_id=v_target_id and q.target_id=actor_id and q.status='PENDING'
    ) then
      raise exception 'INCOMING_MARRIAGE_REQUEST_EXISTS';
    end if;

    if exists(
      select 1 from public.marriage_requests q
      where q.requester_id=actor_id and q.target_id=v_target_id and q.status='PENDING'
    ) then
      raise exception 'MARRIAGE_REQUEST_ALREADY_SENT';
    end if;

    insert into public.marriage_requests(requester_id,target_id,status)
    values(actor_id,v_target_id,'PENDING')
    returning id into request_id;
  else
    if exists(
      select 1 from public.relationships r
      where r.status='ACTIVE'
        and (r.user_a_id in (actor_id,v_target_id) or r.user_b_id in (actor_id,v_target_id))
    ) then
      raise exception 'ALREADY_IN_RELATIONSHIP';
    end if;

    if exists(
      select 1 from public.relationship_requests q
      where q.requester_id=v_target_id and q.target_id=actor_id and q.status='PENDING'
    ) then
      raise exception 'INCOMING_RELATIONSHIP_REQUEST_EXISTS';
    end if;

    if exists(
      select 1 from public.relationship_requests q
      where q.requester_id=actor_id and q.target_id=v_target_id and q.status='PENDING'
    ) then
      raise exception 'RELATIONSHIP_REQUEST_ALREADY_SENT';
    end if;

    insert into public.relationship_requests(requester_id,target_id,status)
    values(actor_id,v_target_id,'PENDING')
    returning id into request_id;
  end if;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data
  )
  select v_target_id,u.telegram_id,'telegram','SOCIAL','Новый запрос',
    actor_name ||
      case when kind='MARRIAGE' then ' отправил вам предложение о браке.'
           else ' отправил вам запрос на связь.' end,
    jsonb_build_object(
      'action',case when kind='MARRIAGE' then 'marriage_request' else 'relationship_request' end,
      'request_id',request_id,
      'source','telegram'
    )
  from public.users u
  where u.id=v_target_id;

  return jsonb_build_object(
    'success',true,
    'kind',kind,
    'request_id',request_id,
    'target_nickname',target_name
  );
end;
$function$;
