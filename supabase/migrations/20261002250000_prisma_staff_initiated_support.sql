-- Allow staff to initiate a support conversation with any Telegram-linked player.

create or replace function public.support_request_seed_message()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  seed_kind text := upper(coalesce(nullif(current_setting('prisma.support.author_kind',true),''),'USER'));
  seed_author_id uuid;
begin
  if seed_kind='STAFF' then
    seed_author_id := nullif(current_setting('prisma.support.author_user_id',true),'')::uuid;
  else
    seed_kind := 'USER';
    seed_author_id := new.user_id;
  end if;

  insert into public.support_messages(
    support_request_id,author_kind,author_user_id,message,delivery_status,created_at
  )
  values(
    new.id,seed_kind,seed_author_id,new.message,
    case when seed_kind='STAFF' then 'pending' else 'stored' end,
    new.created_at
  );
  return new;
end;
$function$;

revoke all on function public.support_request_seed_message() from public,anon,authenticated;
grant execute on function public.support_request_seed_message() to service_role;

create or replace function public.staff_search_support_recipients(
  p_search text default '',
  p_limit integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  q text := trim(coalesce(p_search,''));
  lim integer := greatest(1,least(coalesce(p_limit,25),50));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'support.manage')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by
      case when q<>'' and x.telegram_id::text=q then 0 else 1 end,
      coalesce(x.minecraft_nickname,x.telegram_username,x.full_name,'') asc
    )
    from (
      select u.id,u.telegram_id,u.telegram_username,u.first_name,u.full_name,
             u.minecraft_nickname,u.status,u.platform,u.is_banned
      from public.users u
      where u.deleted_at is null
        and u.telegram_id is not null
        and (
          q='' or
          coalesce(u.minecraft_nickname,'') ilike '%'||q||'%' or
          coalesce(u.telegram_username,'') ilike '%'||replace(q,'@','')||'%' or
          coalesce(u.full_name,'') ilike '%'||q||'%' or
          coalesce(u.first_name,'') ilike '%'||q||'%' or
          u.telegram_id::text like '%'||q||'%' or u.id::text=q
        )
      order by u.updated_at desc
      limit lim
    ) x
  ),'[]'::jsonb);
end;
$function$;

revoke all on function public.staff_search_support_recipients(text,integer) from public,anon;
grant execute on function public.staff_search_support_recipients(text,integer) to authenticated;

create or replace function public.staff_create_support_ticket(
  p_user_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  target public.users%rowtype;
  clean_message text := trim(coalesce(p_message,''));
  request_id uuid;
  created_ticket_no bigint;
  message_id uuid;
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

  select * into target
  from public.users u
  where u.id=p_user_id and u.deleted_at is null
  for update;
  if target.id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if target.telegram_id is null then raise exception 'PLAYER_TELEGRAM_UNAVAILABLE'; end if;
  if target.id=actor_id then raise exception 'SELF_SUPPORT_FORBIDDEN'; end if;

  perform set_config('prisma.support.author_kind','STAFF',true);
  perform set_config('prisma.support.author_user_id',actor_id::text,true);

  insert into public.support_requests(user_id,telegram_id,message,status)
  values(target.id,target.telegram_id,clean_message,'OPEN')
  returning id,ticket_no into request_id,created_ticket_no;

  perform set_config('prisma.support.author_kind','',true);
  perform set_config('prisma.support.author_user_id','',true);

  select sm.id into message_id
  from public.support_messages sm
  where sm.support_request_id=request_id
  order by sm.created_at desc
  limit 1;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  values(
    target.id,target.telegram_id,'telegram','SUPPORT',
    'Сообщение от поддержки PRISMA',
    'Тикет #'||created_ticket_no::text||E'\n\n'||clean_message,
    jsonb_build_object(
      'support_ticket_no',created_ticket_no,
      'support_message_id',message_id,
      'support_event','staff_started'
    ),
    'pending',now()
  );

  return jsonb_build_object(
    'success',true,
    'ticket_no',created_ticket_no,
    'id',request_id,
    'user_id',target.id
  );
end;
$function$;

revoke all on function public.staff_create_support_ticket(uuid,text) from public,anon;
grant execute on function public.staff_create_support_ticket(uuid,text) to authenticated;
