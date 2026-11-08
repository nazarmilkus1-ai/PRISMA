-- PRISMA support center: persistent staff/user message threads and Telegram replies.

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  support_request_id uuid not null references public.support_requests(id) on delete cascade,
  author_kind text not null check (author_kind in ('USER','STAFF')),
  author_user_id uuid references public.users(id) on delete set null,
  message text not null check (char_length(trim(message)) between 1 and 4000),
  delivery_status text not null default 'stored' check (delivery_status in ('stored','pending','sent','failed')),
  delivery_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists support_messages_request_created_idx
  on public.support_messages(support_request_id, created_at desc);
create index if not exists support_messages_author_idx
  on public.support_messages(author_user_id, created_at desc);

alter table public.support_messages enable row level security;
revoke all on table public.support_messages from anon, authenticated;

insert into public.support_messages(
  support_request_id, author_kind, author_user_id, message, delivery_status, created_at
)
select
  s.id, 'USER', s.user_id, s.message, 'stored', s.created_at
from public.support_requests s
where not exists (
  select 1 from public.support_messages sm where sm.support_request_id=s.id
);

create or replace function public.support_request_seed_message()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  insert into public.support_messages(
    support_request_id,author_kind,author_user_id,message,delivery_status,created_at
  )
  values(new.id,'USER',new.user_id,new.message,'stored',new.created_at);
  return new;
end;
$function$;

revoke all on function public.support_request_seed_message() from public,anon,authenticated;
grant execute on function public.support_request_seed_message() to service_role;

drop trigger if exists trg_support_request_seed_message on public.support_requests;
create trigger trg_support_request_seed_message
after insert on public.support_requests
for each row execute function public.support_request_seed_message();

insert into public.permissions(key,description)
values ('support.manage','Просмотр и ответы в технической поддержке PRISMA')
on conflict (key) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where p.key='support.manage'
  and r.name in ('owner','head_admin','head_staff','admin','senior_moderator','moderator')
on conflict do nothing;

create or replace function public.staff_list_support_tickets(
  p_status text default 'OPEN',
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  status_filter text := upper(nullif(trim(coalesce(p_status,'')),''));
  lim integer := greatest(1,least(coalesce(p_limit,100),500));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'support.manage')
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  if status_filter is not null
     and status_filter not in ('OPEN','IN_REVIEW','RESOLVED','CLOSED') then
    raise exception 'INVALID_STATUS';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.updated_at desc, x.ticket_no desc)
    from (
      select
        s.id,s.ticket_no,s.user_id,s.telegram_id,s.status,s.admin_note,
        s.created_at,s.updated_at,s.resolved_at,
        u.minecraft_nickname,u.telegram_username,u.full_name,u.first_name,u.last_name,
        count(sm.id)::integer as message_count,
        max(sm.created_at) as last_message_at
      from public.support_requests s
      left join public.users u on u.id=s.user_id
      left join public.support_messages sm on sm.support_request_id=s.id
      where status_filter is null or s.status=status_filter
      group by
        s.id,s.ticket_no,s.user_id,s.telegram_id,s.status,s.admin_note,
        s.created_at,s.updated_at,s.resolved_at,
        u.minecraft_nickname,u.telegram_username,u.full_name,u.first_name,u.last_name
      order by s.updated_at desc,s.ticket_no desc
      limit lim
    ) x
  ),'[]'::jsonb);
end;
$function$;

revoke all on function public.staff_list_support_tickets(text,integer) from public,anon;
grant execute on function public.staff_list_support_tickets(text,integer) to authenticated;

create or replace function public.staff_get_support_ticket(p_ticket_no bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  v_request public.support_requests%rowtype;
  v_messages jsonb;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'support.manage')
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select * into v_request
  from public.support_requests s
  where s.ticket_no=p_ticket_no
  limit 1;

  if v_request.id is null then raise exception 'SUPPORT_TICKET_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',sm.id,
      'author_kind',sm.author_kind,
      'author_user_id',sm.author_user_id,
      'author_name',coalesce(
        au.telegram_username,
        au.minecraft_nickname,
        au.full_name,
        case when sm.author_kind='STAFF' then 'Сотрудник PRISMA' else 'Пользователь' end
      ),
      'telegram_username',au.telegram_username,
      'minecraft_nickname',au.minecraft_nickname,
      'message',sm.message,
      'delivery_status',sm.delivery_status,
      'delivery_error',sm.delivery_error,
      'created_at',sm.created_at,
      'sent_at',sm.sent_at
    ) order by sm.created_at asc
  ),'[]'::jsonb)
  into v_messages
  from public.support_messages sm
  left join public.users au on au.id=sm.author_user_id
  where sm.support_request_id=v_request.id;

  return jsonb_build_object(
    'ticket',jsonb_build_object(
      'id',v_request.id,
      'ticket_no',v_request.ticket_no,
      'user_id',v_request.user_id,
      'telegram_id',v_request.telegram_id,
      'status',v_request.status,
      'admin_note',v_request.admin_note,
      'created_at',v_request.created_at,
      'updated_at',v_request.updated_at,
      'resolved_at',v_request.resolved_at
    ) ||
    coalesce((
      select jsonb_build_object(
        'minecraft_nickname',u.minecraft_nickname,
        'telegram_username',u.telegram_username,
        'full_name',u.full_name,
        'first_name',u.first_name,
        'last_name',u.last_name,
        'user_status',u.status
      )
      from public.users u
      where u.id=v_request.user_id
    ),'{}'::jsonb),
    'messages',v_messages
  );
end;
$function$;

revoke all on function public.staff_get_support_ticket(bigint) from public,anon;
grant execute on function public.staff_get_support_ticket(bigint) to authenticated;

create or replace function public.staff_reply_support_ticket(
  p_ticket_no bigint,
  p_message text,
  p_close boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  req public.support_requests%rowtype;
  msg_id uuid;
  next_status text;
  clean_message text := trim(coalesce(p_message,''));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(clean_message) not between 1 and 4000 then raise exception 'INVALID_MESSAGE'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'support.manage')
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select * into req
  from public.support_requests s
  where s.ticket_no=p_ticket_no
  for update;

  if req.id is null then raise exception 'SUPPORT_TICKET_NOT_FOUND'; end if;

  next_status := case when coalesce(p_close,false) then 'RESOLVED' else 'IN_REVIEW' end;

  insert into public.support_messages(
    support_request_id,author_kind,author_user_id,message,delivery_status,created_at
  )
  values(req.id,'STAFF',actor_id,clean_message,'pending',now())
  returning id into msg_id;

  update public.support_requests
  set status=next_status,
      updated_at=now(),
      resolved_at=case when next_status='RESOLVED' then now() else null end
  where id=req.id;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  values(
    req.user_id,req.telegram_id,'telegram','SUPPORT',
    'Ответ поддержки PRISMA',
    'Тикет #'||req.ticket_no::text||E'\n\n'||clean_message,
    jsonb_build_object(
      'support_ticket_no',req.ticket_no,
      'support_message_id',msg_id
    ),
    'pending',now()
  );

  return jsonb_build_object(
    'success',true,
    'ticket_no',req.ticket_no,
    'status',next_status,
    'message_id',msg_id
  );
end;
$function$;

revoke all on function public.staff_reply_support_ticket(bigint,text,boolean) from public,anon;
grant execute on function public.staff_reply_support_ticket(bigint,text,boolean) to authenticated;

create or replace function public.staff_set_support_ticket_status(
  p_ticket_no bigint,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  next_status text := upper(trim(coalesce(p_status,'')));
  req public.support_requests%rowtype;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'support.manage')
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  if next_status not in ('OPEN','IN_REVIEW','RESOLVED','CLOSED') then raise exception 'INVALID_STATUS'; end if;

  select * into req
  from public.support_requests s
  where s.ticket_no=p_ticket_no
  for update;

  if req.id is null then raise exception 'SUPPORT_TICKET_NOT_FOUND'; end if;

  update public.support_requests
  set status=next_status,
      updated_at=now(),
      resolved_at=case when next_status in ('RESOLVED','CLOSED') then coalesce(resolved_at,now()) else null end
  where id=req.id;

  return jsonb_build_object('success',true,'ticket_no',p_ticket_no,'status',next_status);
end;
$function$;

revoke all on function public.staff_set_support_ticket_status(bigint,text) from public,anon;
grant execute on function public.staff_set_support_ticket_status(bigint,text) to authenticated;


create or replace function public.bot_mark_support_message_delivery(
  p_message_id uuid,
  p_status text,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare
  next_status text := lower(trim(coalesce(p_status,'')));
begin
  if next_status not in ('pending','sent','failed','stored') then
    raise exception 'INVALID_DELIVERY_STATUS';
  end if;

  update public.support_messages
  set delivery_status=next_status,
      delivery_error=case when next_status='failed' then left(coalesce(p_error,''),2000) else null end,
      sent_at=case when next_status='sent' then coalesce(sent_at,now()) else sent_at end
  where id=p_message_id;

  return found;
end;
$function$;

revoke all on function public.bot_mark_support_message_delivery(uuid,text,text) from public,anon,authenticated;
grant execute on function public.bot_mark_support_message_delivery(uuid,text,text) to service_role;
