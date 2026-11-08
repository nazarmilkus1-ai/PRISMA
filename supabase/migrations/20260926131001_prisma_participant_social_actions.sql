-- Participant social action gateway: request/respond/cancel/end without exposing
-- Telegram-oriented bot RPCs to authenticated web clients.
create or replace function private.prisma_participant_social_action(
  p_user_id uuid,p_action text,p_target_nickname text default null,p_request_id uuid default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  action text:=upper(trim(coalesce(p_action,'')));
  v_target_id uuid;
  row_id uuid;
  partner_id uuid;
  requester_name text;
  target_name text;
  request_row public.marriage_requests%rowtype;
  relation_request_row public.relationship_requests%rowtype;
  lo uuid;
  hi uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);

  if action in ('MARRIAGE_REQUEST','RELATIONSHIP_REQUEST','RELATIONSHIP_END') then
    select u.id,u.minecraft_nickname into v_target_id,target_name
    from public.users u
    where u.deleted_at is null and u.status='ACCEPTED'::public.application_status
      and not u.is_banned
      and lower(u.minecraft_nickname)=lower(trim(coalesce(p_target_nickname,'')))
    limit 1;
    if v_target_id is null then raise exception 'TARGET_NOT_FOUND'; end if;
    if v_target_id=p_user_id then raise exception 'SELF_TARGET_FORBIDDEN'; end if;
  end if;

  if action in ('MARRIAGE_REQUEST','RELATIONSHIP_REQUEST') then
    perform 1 from public.users u where u.id in (p_user_id,v_target_id) order by u.id for update;
  end if;

  if action='MARRIAGE_REQUEST' then
    if exists(select 1 from public.marriages m where m.status='ACTIVE' and (m.user_a_id in (p_user_id,v_target_id) or m.user_b_id in (p_user_id,v_target_id))) then raise exception 'ALREADY_MARRIED'; end if;
    if exists(select 1 from public.marriage_requests q where q.requester_id=v_target_id and q.target_id=p_user_id and q.status='PENDING') then raise exception 'INCOMING_MARRIAGE_REQUEST_EXISTS'; end if;
    if exists(select 1 from public.marriage_requests q where q.requester_id=p_user_id and q.target_id=v_target_id and q.status='PENDING') then raise exception 'MARRIAGE_REQUEST_ALREADY_SENT'; end if;
    insert into public.marriage_requests(requester_id,target_id,status) values(p_user_id,v_target_id,'PENDING') returning id into row_id;
    select u.minecraft_nickname into requester_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select v_target_id,t.telegram_id,'telegram','SOCIAL','Новый запрос',coalesce(requester_name,'Игрок')||' отправил вам запрос на брак.',
      jsonb_build_object('action','marriage_request','request_id',row_id,'source','participant_site')
    from public.users t where t.id=v_target_id;
    return jsonb_build_object('success',true,'action',action,'request_id',row_id);
  end if;

  if action='RELATIONSHIP_REQUEST' then
    if exists(select 1 from public.relationships r where r.status='ACTIVE' and (r.user_a_id in (p_user_id,v_target_id) or r.user_b_id in (p_user_id,v_target_id))) then raise exception 'ALREADY_IN_RELATIONSHIP'; end if;
    if exists(select 1 from public.relationship_requests q where q.requester_id=v_target_id and q.target_id=p_user_id and q.status='PENDING') then raise exception 'INCOMING_RELATIONSHIP_REQUEST_EXISTS'; end if;
    if exists(select 1 from public.relationship_requests q where q.requester_id=p_user_id and q.target_id=v_target_id and q.status='PENDING') then raise exception 'RELATIONSHIP_REQUEST_ALREADY_SENT'; end if;
    insert into public.relationship_requests(requester_id,target_id,status) values(p_user_id,v_target_id,'PENDING') returning id into row_id;
    select u.minecraft_nickname into requester_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select v_target_id,t.telegram_id,'telegram','SOCIAL','Новый запрос',coalesce(requester_name,'Игрок')||' отправил вам запрос на связь.',
      jsonb_build_object('action','relationship_request','request_id',row_id,'source','participant_site')
    from public.users t where t.id=v_target_id;
    return jsonb_build_object('success',true,'action',action,'request_id',row_id);
  end if;

  if action in ('MARRIAGE_ACCEPT','MARRIAGE_REJECT','MARRIAGE_CANCEL_REQUEST') then
    select * into request_row from public.marriage_requests q
    where q.id=coalesce(p_request_id,'00000000-0000-0000-0000-000000000000'::uuid)
      and (q.target_id=p_user_id or q.requester_id=p_user_id) and q.status='PENDING' for update;
    if not found then raise exception 'MARRIAGE_REQUEST_NOT_FOUND'; end if;
    if action='MARRIAGE_CANCEL_REQUEST' then
      if request_row.requester_id<>p_user_id then raise exception 'SOCIAL_REQUEST_FORBIDDEN'; end if;
      update public.marriage_requests set status='CANCELLED',responded_at=now() where id=request_row.id;
      return jsonb_build_object('success',true,'action',action);
    end if;
    if request_row.target_id<>p_user_id then raise exception 'SOCIAL_REQUEST_FORBIDDEN'; end if;
    perform 1 from public.users u where u.id in (p_user_id,request_row.requester_id) order by u.id for update;
    if action='MARRIAGE_REJECT' then
      update public.marriage_requests set status='REJECTED',responded_at=now() where id=request_row.id;
    else
      if exists(select 1 from public.marriages m where m.status='ACTIVE' and (m.user_a_id in (p_user_id,request_row.requester_id) or m.user_b_id in (p_user_id,request_row.requester_id))) then raise exception 'ALREADY_MARRIED'; end if;
      if request_row.requester_id<p_user_id then lo:=request_row.requester_id;hi:=p_user_id; else lo:=p_user_id;hi:=request_row.requester_id; end if;
      insert into public.marriages(user_a_id,user_b_id,status) values(lo,hi,'ACTIVE') returning id into row_id;
      update public.marriage_requests set status='ACCEPTED',responded_at=now() where id=request_row.id;
    end if;
    select u.minecraft_nickname into target_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select request_row.requester_id,u.telegram_id,'telegram','SOCIAL',
      case when action='MARRIAGE_ACCEPT' then 'Запрос принят' else 'Запрос отклонён' end,
      case when action='MARRIAGE_ACCEPT' then coalesce(target_name,'Игрок')||' принял ваш запрос на брак.'
           else coalesce(target_name,'Игрок')||' отклонил ваш запрос на брак.' end,
      jsonb_build_object('action',lower(action),'request_id',request_row.id,'source','participant_site')
    from public.users u where u.id=request_row.requester_id;
    return jsonb_build_object('success',true,'action',action,'accepted',action='MARRIAGE_ACCEPT','marriage_id',row_id);
  end if;

  if action in ('RELATIONSHIP_ACCEPT','RELATIONSHIP_REJECT','RELATIONSHIP_CANCEL_REQUEST') then
    select * into relation_request_row from public.relationship_requests q
    where q.id=coalesce(p_request_id,'00000000-0000-0000-0000-000000000000'::uuid)
      and (q.target_id=p_user_id or q.requester_id=p_user_id) and q.status='PENDING' for update;
    if not found then raise exception 'RELATIONSHIP_REQUEST_NOT_FOUND'; end if;
    if action='RELATIONSHIP_CANCEL_REQUEST' then
      if relation_request_row.requester_id<>p_user_id then raise exception 'SOCIAL_REQUEST_FORBIDDEN'; end if;
      update public.relationship_requests set status='CANCELLED',responded_at=now() where id=relation_request_row.id;
      return jsonb_build_object('success',true,'action',action);
    end if;
    if relation_request_row.target_id<>p_user_id then raise exception 'SOCIAL_REQUEST_FORBIDDEN'; end if;
    perform 1 from public.users u where u.id in (p_user_id,relation_request_row.requester_id) order by u.id for update;
    if action='RELATIONSHIP_REJECT' then
      update public.relationship_requests set status='REJECTED',responded_at=now() where id=relation_request_row.id;
    else
      if exists(select 1 from public.relationships r where r.status='ACTIVE' and (r.user_a_id in (p_user_id,relation_request_row.requester_id) or r.user_b_id in (p_user_id,relation_request_row.requester_id))) then raise exception 'ALREADY_IN_RELATIONSHIP'; end if;
      if relation_request_row.requester_id<p_user_id then lo:=relation_request_row.requester_id;hi:=p_user_id; else lo:=p_user_id;hi:=relation_request_row.requester_id; end if;
      insert into public.relationships(user_a_id,user_b_id,status) values(lo,hi,'ACTIVE') returning id into row_id;
      update public.relationship_requests set status='ACCEPTED',responded_at=now() where id=relation_request_row.id;
    end if;
    select u.minecraft_nickname into target_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select relation_request_row.requester_id,u.telegram_id,'telegram','SOCIAL',
      case when action='RELATIONSHIP_ACCEPT' then 'Запрос принят' else 'Запрос отклонён' end,
      case when action='RELATIONSHIP_ACCEPT' then coalesce(target_name,'Игрок')||' принял ваш запрос на связь.'
           else coalesce(target_name,'Игрок')||' отклонил ваш запрос на связь.' end,
      jsonb_build_object('action',lower(action),'request_id',relation_request_row.id,'source','participant_site')
    from public.users u where u.id=relation_request_row.requester_id;
    return jsonb_build_object('success',true,'action',action,'accepted',action='RELATIONSHIP_ACCEPT','relationship_id',row_id);
  end if;

  if action='MARRIAGE_DIVORCE' then
    select case when m.user_a_id=p_user_id then m.user_b_id else m.user_a_id end into partner_id
    from public.marriages m
    where m.status='ACTIVE' and (m.user_a_id=p_user_id or m.user_b_id=p_user_id)
    order by m.married_at desc limit 1 for update;
    if partner_id is null then raise exception 'NO_ACTIVE_MARRIAGE'; end if;
    perform 1 from public.users u where u.id in (p_user_id,partner_id) order by u.id for update;
    update public.marriages set status='DIVORCED',divorced_at=now()
    where status='ACTIVE' and (user_a_id=p_user_id or user_b_id=p_user_id) returning id into row_id;
    select u.minecraft_nickname into target_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select partner_id,u.telegram_id,'telegram','SOCIAL','Статус изменён',coalesce(target_name,'Игрок')||' завершил действующий брак.',
      jsonb_build_object('action','marriage_divorce','source','participant_site')
    from public.users u where u.id=partner_id;
    return jsonb_build_object('success',true,'action',action,'marriage_id',row_id);
  end if;

  if action='RELATIONSHIP_END' then
    perform 1 from public.users u where u.id in (p_user_id,v_target_id) order by u.id for update;
    update public.relationships set status='ENDED',ended_at=now()
    where status='ACTIVE' and ((user_a_id=p_user_id and user_b_id=v_target_id) or (user_a_id=v_target_id and user_b_id=p_user_id))
    returning id into row_id;
    if row_id is null then raise exception 'RELATIONSHIP_NOT_FOUND'; end if;
    select u.minecraft_nickname into requester_name from public.users u where u.id=p_user_id;
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select v_target_id,u.telegram_id,'telegram','SOCIAL','Статус изменён',coalesce(requester_name,'Игрок')||' завершил действующую связь.',
      jsonb_build_object('action','relationship_end','source','participant_site')
    from public.users u where u.id=v_target_id;
    return jsonb_build_object('success',true,'action',action,'relationship_id',row_id);
  end if;

  raise exception 'INVALID_SOCIAL_ACTION';
end;
$function$;

create or replace function public.participant_social_action(
  p_action text,p_target_nickname text default null,p_request_id uuid default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_social_action(uid,p_action,p_target_nickname,p_request_id);
end;
$function$;

revoke all on function public.participant_social_action(text,text,uuid) from public,anon;
grant execute on function public.participant_social_action(text,text,uuid) to authenticated;

-- Keep the read gateway consistent with the action gateway and expose only
-- request metadata needed by the participant profile.
create or replace function private.prisma_participant_get_social(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare result jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);
  select jsonb_build_object(
    'marriage',coalesce((select jsonb_build_object('id',m.id,'partner_id',p.id,'partner_nickname',p.minecraft_nickname,'married_at',m.married_at,'source',m.source)
      from public.marriages m join public.users p on p.id=case when m.user_a_id=p_user_id then m.user_b_id else m.user_a_id end
      where m.status='ACTIVE' and (m.user_a_id=p_user_id or m.user_b_id=p_user_id) and p.deleted_at is null order by m.married_at desc limit 1),'null'::jsonb),
    'relationship',coalesce((select jsonb_build_object('id',r.id,'partner_id',p.id,'partner_nickname',p.minecraft_nickname,'started_at',r.started_at)
      from public.relationships r join public.users p on p.id=case when r.user_a_id=p_user_id then r.user_b_id else r.user_a_id end
      where r.status='ACTIVE' and (r.user_a_id=p_user_id or r.user_b_id=p_user_id) and p.deleted_at is null order by r.started_at desc limit 1),'null'::jsonb),
    'marriage_history',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'partner_nickname',p.minecraft_nickname,'status',h.status,'married_at',h.married_at,'divorced_at',h.divorced_at) order by h.married_at desc)
      from (select m.id,m.user_a_id,m.user_b_id,m.status,m.married_at,m.divorced_at from public.marriages m where m.user_a_id=p_user_id or m.user_b_id=p_user_id order by m.married_at desc limit 20) h
      join public.users p on p.id=case when h.user_a_id=p_user_id then h.user_b_id else h.user_a_id end where p.deleted_at is null),'[]'::jsonb),
    'relationship_history',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'partner_nickname',p.minecraft_nickname,'status',h.status,'started_at',h.started_at,'ended_at',h.ended_at) order by h.started_at desc)
      from (select r.id,r.user_a_id,r.user_b_id,r.status,r.started_at,r.ended_at from public.relationships r where r.user_a_id=p_user_id or r.user_b_id=p_user_id order by r.started_at desc limit 20) h
      join public.users p on p.id=case when h.user_a_id=p_user_id then h.user_b_id else h.user_a_id end where p.deleted_at is null),'[]'::jsonb),
    'marriage_requests_in',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'requester_nickname',u.minecraft_nickname,'created_at',q.created_at) order by q.created_at desc)
      from (select id,requester_id,created_at from public.marriage_requests where target_id=p_user_id and status='PENDING' order by created_at desc limit 10) q
      join public.users u on u.id=q.requester_id where u.deleted_at is null),'[]'::jsonb),
    'relationship_requests_in',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'requester_nickname',u.minecraft_nickname,'created_at',q.created_at) order by q.created_at desc)
      from (select id,requester_id,created_at from public.relationship_requests where target_id=p_user_id and status='PENDING' order by created_at desc limit 10) q
      join public.users u on u.id=q.requester_id where u.deleted_at is null),'[]'::jsonb),
    'marriage_requests_out',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'target_nickname',u.minecraft_nickname,'created_at',q.created_at) order by q.created_at desc)
      from (select id,target_id,created_at from public.marriage_requests where requester_id=p_user_id and status='PENDING' order by created_at desc limit 10) q
      join public.users u on u.id=q.target_id where u.deleted_at is null),'[]'::jsonb),
    'relationship_requests_out',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'target_nickname',u.minecraft_nickname,'created_at',q.created_at) order by q.created_at desc)
      from (select id,target_id,created_at from public.relationship_requests where requester_id=p_user_id and status='PENDING' order by created_at desc limit 10) q
      join public.users u on u.id=q.target_id where u.deleted_at is null),'[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

revoke execute on function private.prisma_participant_social_action(uuid,text,text,uuid) from public,anon,authenticated;