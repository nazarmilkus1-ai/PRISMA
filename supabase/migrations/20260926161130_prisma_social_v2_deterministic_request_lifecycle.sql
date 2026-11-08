-- PRISMA social v2: deterministic request lifecycle for Telegram and participant clients.

create index if not exists relationship_requests_requester_idx
  on public.relationship_requests(requester_id,status,created_at desc);
create index if not exists marriage_requests_requester_idx
  on public.marriage_requests(requester_id,status,created_at desc);
create index if not exists relationships_user_pair_idx
  on public.relationships(user_a_id,user_b_id,status);
create index if not exists marriages_user_pair_idx
  on public.marriages(user_a_id,user_b_id,status);

create or replace function private.prisma_bot_social_require_user(p_tg_id bigint)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and u.is_whitelisted
    and not u.is_banned
  limit 1;

  if uid is null then
    raise exception 'PLAYER_ACCESS_REQUIRED';
  end if;
  return uid;
end;
$function$;

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

create or replace function private.prisma_bot_social_info(p_tg_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  result jsonb;
begin
  uid:=private.prisma_bot_social_require_user(p_tg_id);

  select jsonb_build_object(
    'marriage',coalesce((
      select jsonb_build_object(
        'id',m.id,
        'partner_tg_id',p.telegram_id,
        'partner_nickname',coalesce(p.minecraft_nickname,p.full_name,p.telegram_username,'Игрок'),
        'married_at',m.married_at
      )
      from public.marriages m
      join public.users p
        on p.id=case when m.user_a_id=uid then m.user_b_id else m.user_a_id end
      where m.status='ACTIVE'
        and (m.user_a_id=uid or m.user_b_id=uid)
        and p.deleted_at is null
      order by m.married_at desc
      limit 1
    ),'null'::jsonb),
    'relationship',coalesce((
      select jsonb_build_object(
        'id',r.id,
        'partner_tg_id',p.telegram_id,
        'partner_nickname',coalesce(p.minecraft_nickname,p.full_name,p.telegram_username,'Игрок'),
        'started_at',r.started_at
      )
      from public.relationships r
      join public.users p
        on p.id=case when r.user_a_id=uid then r.user_b_id else r.user_a_id end
      where r.status='ACTIVE'
        and (r.user_a_id=uid or r.user_b_id=uid)
        and p.deleted_at is null
      order by r.started_at desc
      limit 1
    ),'null'::jsonb),
    'marriage_requests_in',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',q.id,
        'requester_tg_id',u.telegram_id,
        'requester_nickname',coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок'),
        'created_at',q.created_at
      ) order by q.created_at desc)
      from public.marriage_requests q
      join public.users u on u.id=q.requester_id
      where q.target_id=uid
        and q.status='PENDING'
        and u.deleted_at is null
      limit 10
    ),'[]'::jsonb),
    'relationship_requests_in',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',q.id,
        'requester_tg_id',u.telegram_id,
        'requester_nickname',coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок'),
        'created_at',q.created_at
      ) order by q.created_at desc)
      from public.relationship_requests q
      join public.users u on u.id=q.requester_id
      where q.target_id=uid
        and q.status='PENDING'
        and u.deleted_at is null
      limit 10
    ),'[]'::jsonb),
    'marriage_requests_out',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',q.id,
        'target_tg_id',u.telegram_id,
        'target_nickname',coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок'),
        'created_at',q.created_at
      ) order by q.created_at desc)
      from public.marriage_requests q
      join public.users u on u.id=q.target_id
      where q.requester_id=uid
        and q.status='PENDING'
        and u.deleted_at is null
      limit 10
    ),'[]'::jsonb),
    'relationship_requests_out',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',q.id,
        'target_tg_id',u.telegram_id,
        'target_nickname',coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок'),
        'created_at',q.created_at
      ) order by q.created_at desc)
      from public.relationship_requests q
      join public.users u on u.id=q.target_id
      where q.requester_id=uid
        and q.status='PENDING'
        and u.deleted_at is null
      limit 10
    ),'[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

create or replace function private.prisma_bot_social_respond(
  p_tg_id bigint,
  p_kind text,
  p_request_id uuid,
  p_accept boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  kind text:=upper(trim(coalesce(p_kind,'')));
  requester_id uuid;
  target_id uuid;
  partner_name text;
  row_id uuid;
begin
  uid:=private.prisma_bot_social_require_user(p_tg_id);
  if p_request_id is null then raise exception 'SOCIAL_REQUEST_NOT_FOUND'; end if;
  if kind not in ('MARRIAGE','RELATIONSHIP') then raise exception 'INVALID_SOCIAL_KIND'; end if;

  if kind='MARRIAGE' then
    select q.requester_id,q.target_id
      into requester_id,target_id
    from public.marriage_requests q
    where q.id=p_request_id
      and q.target_id=uid
      and q.status='PENDING'
    for update;
    if requester_id is null then raise exception 'MARRIAGE_REQUEST_NOT_FOUND'; end if;
  else
    select q.requester_id,q.target_id
      into requester_id,target_id
    from public.relationship_requests q
    where q.id=p_request_id
      and q.target_id=uid
      and q.status='PENDING'
    for update;
    if requester_id is null then raise exception 'RELATIONSHIP_REQUEST_NOT_FOUND'; end if;
  end if;

  perform 1
  from public.users u
  where u.id in (uid,requester_id)
  order by u.id
  for update;

  if not p_accept then
    if kind='MARRIAGE' then
      update public.marriage_requests
      set status='REJECTED',responded_at=now()
      where id=p_request_id;
    else
      update public.relationship_requests
      set status='REJECTED',responded_at=now()
      where id=p_request_id;
    end if;

    select coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок')
      into partner_name
    from public.users u where u.id=uid;

    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select requester_id,u.telegram_id,'telegram','SOCIAL','Запрос отклонён',
      partner_name ||
        case when kind='MARRIAGE' then ' отклонил ваше предложение о браке.'
             else ' отклонил ваш запрос на связь.' end,
      jsonb_build_object(
        'action',case when kind='MARRIAGE' then 'marriage_rejected' else 'relationship_rejected' end,
        'request_id',p_request_id,
        'source','telegram'
      )
    from public.users u where u.id=requester_id;

    return jsonb_build_object('success',true,'accepted',false,'kind',kind,'request_id',p_request_id);
  end if;

  if kind='MARRIAGE' then
    if exists(
      select 1 from public.marriages m
      where m.status='ACTIVE'
        and (m.user_a_id in (uid,requester_id) or m.user_b_id in (uid,requester_id))
    ) then
      raise exception 'ALREADY_MARRIED';
    end if;

    if requester_id<uid then
      insert into public.marriages(user_a_id,user_b_id,status)
      values(requester_id,uid,'ACTIVE')
      returning id into row_id;
    else
      insert into public.marriages(user_a_id,user_b_id,status)
      values(uid,requester_id,'ACTIVE')
      returning id into row_id;
    end if;

    update public.marriage_requests
    set status='ACCEPTED',responded_at=now()
    where id=p_request_id;
  else
    if exists(
      select 1 from public.relationships r
      where r.status='ACTIVE'
        and (r.user_a_id in (uid,requester_id) or r.user_b_id in (uid,requester_id))
    ) then
      raise exception 'ALREADY_IN_RELATIONSHIP';
    end if;

    if requester_id<uid then
      insert into public.relationships(user_a_id,user_b_id,status)
      values(requester_id,uid,'ACTIVE')
      returning id into row_id;
    else
      insert into public.relationships(user_a_id,user_b_id,status)
      values(uid,requester_id,'ACTIVE')
      returning id into row_id;
    end if;

    update public.relationship_requests
    set status='ACCEPTED',responded_at=now()
    where id=p_request_id;
  end if;

  select coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок')
    into partner_name
  from public.users u where u.id=uid;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select requester_id,u.telegram_id,'telegram','SOCIAL','Запрос принят',
    partner_name ||
      case when kind='MARRIAGE' then ' принял ваше предложение о браке.'
           else ' принял ваш запрос на связь.' end,
    jsonb_build_object(
      'action',case when kind='MARRIAGE' then 'marriage_accepted' else 'relationship_accepted' end,
      'request_id',p_request_id,
      'source','telegram'
    )
  from public.users u where u.id=requester_id;

  return jsonb_build_object(
    'success',true,'accepted',true,'kind',kind,'request_id',p_request_id,'social_id',row_id
  );
end;
$function$;

create or replace function private.prisma_bot_social_cancel(
  p_tg_id bigint,
  p_kind text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  kind text:=upper(trim(coalesce(p_kind,'')));
  target_id uuid;
begin
  uid:=private.prisma_bot_social_require_user(p_tg_id);
  if p_request_id is null then raise exception 'SOCIAL_REQUEST_NOT_FOUND'; end if;
  if kind not in ('MARRIAGE','RELATIONSHIP') then raise exception 'INVALID_SOCIAL_KIND'; end if;

  if kind='MARRIAGE' then
    select q.target_id into target_id
    from public.marriage_requests q
    where q.id=p_request_id and q.requester_id=uid and q.status='PENDING'
    for update;
    if target_id is null then raise exception 'MARRIAGE_REQUEST_NOT_FOUND'; end if;
    update public.marriage_requests set status='CANCELLED',responded_at=now() where id=p_request_id;
  else
    select q.target_id into target_id
    from public.relationship_requests q
    where q.id=p_request_id and q.requester_id=uid and q.status='PENDING'
    for update;
    if target_id is null then raise exception 'RELATIONSHIP_REQUEST_NOT_FOUND'; end if;
    update public.relationship_requests set status='CANCELLED',responded_at=now() where id=p_request_id;
  end if;

  return jsonb_build_object('success',true,'kind',kind,'request_id',p_request_id);
end;
$function$;

create or replace function private.prisma_bot_social_end(
  p_tg_id bigint,
  p_kind text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
  kind text:=upper(trim(coalesce(p_kind,'')));
  partner_id uuid;
  row_id uuid;
  actor_name text;
begin
  uid:=private.prisma_bot_social_require_user(p_tg_id);
  if kind not in ('MARRIAGE','RELATIONSHIP') then raise exception 'INVALID_SOCIAL_KIND'; end if;

  if kind='MARRIAGE' then
    select case when m.user_a_id=uid then m.user_b_id else m.user_a_id end,m.id
      into partner_id,row_id
    from public.marriages m
    where m.status='ACTIVE' and (m.user_a_id=uid or m.user_b_id=uid)
    order by m.married_at desc
    limit 1
    for update;
    if partner_id is null then raise exception 'NO_ACTIVE_MARRIAGE'; end if;

    perform 1 from public.users u where u.id in (uid,partner_id) order by u.id for update;
    update public.marriages set status='DIVORCED',divorced_at=now()
    where id=row_id;
  else
    select case when r.user_a_id=uid then r.user_b_id else r.user_a_id end,r.id
      into partner_id,row_id
    from public.relationships r
    where r.status='ACTIVE' and (r.user_a_id=uid or r.user_b_id=uid)
    order by r.started_at desc
    limit 1
    for update;
    if partner_id is null then raise exception 'RELATIONSHIP_NOT_FOUND'; end if;

    perform 1 from public.users u where u.id in (uid,partner_id) order by u.id for update;
    update public.relationships set status='ENDED',ended_at=now()
    where id=row_id;
  end if;

  select coalesce(u.minecraft_nickname,u.full_name,u.telegram_username,'Игрок')
    into actor_name
  from public.users u where u.id=uid;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select partner_id,u.telegram_id,'telegram','SOCIAL','Статус изменён',
    actor_name ||
      case when kind='MARRIAGE' then ' расторг брак.' else ' завершил связь.' end,
    jsonb_build_object(
      'action',case when kind='MARRIAGE' then 'marriage_divorce' else 'relationship_end' end,
      'social_id',row_id,
      'source','telegram'
    )
  from public.users u where u.id=partner_id;

  return jsonb_build_object('success',true,'kind',kind,'social_id',row_id);
end;
$function$;

create or replace function public.bot_social_request(p_tg_id bigint,p_target_tg_id bigint,p_kind text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  return private.prisma_bot_social_request(p_tg_id,p_target_tg_id,p_kind);
end;
$function$;

create or replace function public.bot_social_info(p_tg_id bigint)
returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
begin
  return private.prisma_bot_social_info(p_tg_id);
end;
$function$;

create or replace function public.bot_social_respond(
  p_tg_id bigint,p_kind text,p_request_id uuid,p_accept boolean
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  return private.prisma_bot_social_respond(p_tg_id,p_kind,p_request_id,p_accept);
end;
$function$;

create or replace function public.bot_social_cancel(
  p_tg_id bigint,p_kind text,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  return private.prisma_bot_social_cancel(p_tg_id,p_kind,p_request_id);
end;
$function$;

create or replace function public.bot_social_end(p_tg_id bigint,p_kind text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  return private.prisma_bot_social_end(p_tg_id,p_kind);
end;
$function$;

revoke all on function public.bot_social_request(bigint,bigint,text) from public,anon,authenticated;
revoke all on function public.bot_social_info(bigint) from public,anon,authenticated;
revoke all on function public.bot_social_respond(bigint,text,uuid,boolean) from public,anon,authenticated;
revoke all on function public.bot_social_cancel(bigint,text,uuid) from public,anon,authenticated;
revoke all on function public.bot_social_end(bigint,text) from public,anon,authenticated;

grant execute on function public.bot_social_request(bigint,bigint,text) to service_role;
grant execute on function public.bot_social_info(bigint) to service_role;
grant execute on function public.bot_social_respond(bigint,text,uuid,boolean) to service_role;
grant execute on function public.bot_social_cancel(bigint,text,uuid) to service_role;
grant execute on function public.bot_social_end(bigint,text) to service_role;

revoke all on function private.prisma_bot_social_require_user(bigint) from public,anon,authenticated;
revoke all on function private.prisma_bot_social_request(bigint,bigint,text) from public,anon,authenticated;
revoke all on function private.prisma_bot_social_info(bigint) from public,anon,authenticated;
revoke all on function private.prisma_bot_social_respond(bigint,text,uuid,boolean) from public,anon,authenticated;
revoke all on function private.prisma_bot_social_cancel(bigint,text,uuid) from public,anon,authenticated;
revoke all on function private.prisma_bot_social_end(bigint,text) from public,anon,authenticated;
