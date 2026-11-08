-- Participant-facing technical support: own tickets and follow-up messages.

create or replace function public.participant_list_support_tickets(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  lim integer := greatest(1,least(coalesce(p_limit,50),100));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
  if actor_id is null then raise exception 'USER_NOT_FOUND'; end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.updated_at desc,x.ticket_no desc)
    from (
      select s.id,s.ticket_no,s.status,s.created_at,s.updated_at,s.resolved_at,
             count(sm.id)::integer as message_count,
             max(sm.created_at) as last_message_at
      from public.support_requests s
      left join public.support_messages sm on sm.support_request_id=s.id
      where s.user_id=actor_id
      group by s.id,s.ticket_no,s.status,s.created_at,s.updated_at,s.resolved_at
      order by s.updated_at desc,s.ticket_no desc
      limit lim
    ) x
  ),'[]'::jsonb);
end;
$function$;
revoke all on function public.participant_list_support_tickets(integer) from public,anon;
grant execute on function public.participant_list_support_tickets(integer) to authenticated;

create or replace function public.participant_get_support_ticket(p_ticket_no bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  req public.support_requests%rowtype;
  messages_data jsonb;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
  if actor_id is null then raise exception 'USER_NOT_FOUND'; end if;

  select * into req
  from public.support_requests s
  where s.ticket_no=p_ticket_no and s.user_id=actor_id
  limit 1;
  if req.id is null then raise exception 'SUPPORT_TICKET_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',sm.id,'author_kind',sm.author_kind,'message',sm.message,
    'created_at',sm.created_at,'delivery_status',sm.delivery_status,'sent_at',sm.sent_at
  ) order by sm.created_at asc),'[]'::jsonb)
  into messages_data
  from public.support_messages sm
  where sm.support_request_id=req.id;

  return jsonb_build_object(
    'ticket',jsonb_build_object(
      'id',req.id,'ticket_no',req.ticket_no,'status',req.status,
      'created_at',req.created_at,'updated_at',req.updated_at,'resolved_at',req.resolved_at
    ),
    'messages',messages_data
  );
end;
$function$;
revoke all on function public.participant_get_support_ticket(bigint) from public,anon;
grant execute on function public.participant_get_support_ticket(bigint) to authenticated;

create or replace function public.participant_create_support_ticket(p_message text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  tg_id bigint;
  actor_name text;
  clean_message text := trim(coalesce(p_message,''));
  used_today integer;
  daily_limit integer := 2;
  request_id uuid;
  created_ticket_no bigint;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(clean_message) not between 3 and 4000 then raise exception 'INVALID_MESSAGE'; end if;

  select u.id,u.telegram_id,coalesce(u.minecraft_nickname,u.full_name,u.first_name,'Участник PRISMA')
  into actor_id,tg_id,actor_name
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
  limit 1;
  if actor_id is null then raise exception 'USER_NOT_FOUND'; end if;

  perform pg_advisory_xact_lock(hashtextextended(actor_id::text, 0));

  select count(*)::integer into used_today
  from public.support_requests s
  where s.user_id=actor_id
    and s.created_at >= date_trunc('day',now());

  if used_today >= daily_limit then raise exception 'DAILY_LIMIT'; end if;

  insert into public.support_requests(user_id,telegram_id,message,status)
  values(actor_id,tg_id,clean_message,'OPEN')
  returning id,ticket_no into request_id,created_ticket_no;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select distinct staff_user.id,staff_user.telegram_id,'telegram','SUPPORT',
    'Новое обращение в поддержку PRISMA',
    'Тикет #'||created_ticket_no::text||' от '||actor_name||'. Откройте раздел «Техническая поддержка» в панели PRISMA.',
    jsonb_build_object('support_ticket_no',created_ticket_no,'support_event','created'),
    'pending',now()
  from public.users staff_user
  join public.admins a on a.user_id=staff_user.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id and p.key='support.manage'
  where staff_user.deleted_at is null and staff_user.telegram_id is not null;

  return jsonb_build_object(
    'success',true,'ticket_no',created_ticket_no,'id',request_id,
    'remaining',greatest(daily_limit-used_today-1,0),'limit',daily_limit
  );
end;
$function$;
revoke all on function public.participant_create_support_ticket(text) from public,anon;
grant execute on function public.participant_create_support_ticket(text) to authenticated;

create or replace function public.participant_reply_support_ticket(p_ticket_no bigint,p_message text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  actor_name text;
  req public.support_requests%rowtype;
  clean_message text := trim(coalesce(p_message,''));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(clean_message) not between 1 and 4000 then raise exception 'INVALID_MESSAGE'; end if;

  select u.id,coalesce(u.minecraft_nickname,u.full_name,u.first_name,'Участник PRISMA')
  into actor_id,actor_name
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
  if actor_id is null then raise exception 'USER_NOT_FOUND'; end if;

  select * into req
  from public.support_requests s
  where s.ticket_no=p_ticket_no and s.user_id=actor_id
  for update;
  if req.id is null then raise exception 'SUPPORT_TICKET_NOT_FOUND'; end if;
  if req.status in ('RESOLVED','CLOSED') then raise exception 'SUPPORT_TICKET_CLOSED'; end if;

  insert into public.support_messages(
    support_request_id,author_kind,author_user_id,message,delivery_status,created_at
  ) values(req.id,'USER',actor_id,clean_message,'stored',now());

  update public.support_requests
  set status='OPEN',updated_at=now()
  where id=req.id;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select distinct staff_user.id,staff_user.telegram_id,'telegram','SUPPORT',
    'Новое сообщение в поддержке PRISMA',
    actor_name||' ответил в тикете #'||req.ticket_no::text||'. Откройте раздел «Техническая поддержка» в панели PRISMA.',
    jsonb_build_object('support_ticket_no',req.ticket_no,'support_event','reply'),
    'pending',now()
  from public.users staff_user
  join public.admins a on a.user_id=staff_user.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id and p.key='support.manage'
  where staff_user.deleted_at is null and staff_user.telegram_id is not null;

  return jsonb_build_object('success',true,'ticket_no',req.ticket_no);
end;
$function$;

revoke all on function public.participant_reply_support_ticket(bigint,text) from public,anon;
grant execute on function public.participant_reply_support_ticket(bigint,text) to authenticated;
