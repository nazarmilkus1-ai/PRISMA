-- PRISMA 2.1.0 bridge hardening.
-- Forward-only patch: leased queue tokens prevent stale workers from finalizing
-- another worker's claim; rate-limit checks are serialized per sender; Minecraft
-- messages require an already-bound UUID, not just a matching display nickname.

alter table public.minecraft_chat_bridge_queue
  add column if not exists lease_token uuid;

create index if not exists minecraft_chat_bridge_processing_idx
  on public.minecraft_chat_bridge_queue(direction, claimed_at)
  where status='PROCESSING';

create or replace function public.mc_bridge_enqueue_from_minecraft(
  p_user_id uuid,
  p_minecraft_uuid uuid,
  p_nickname text,
  p_world text,
  p_message text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  identity_id uuid;
  normalized_message text;
  normalized_nickname text := btrim(coalesce(p_nickname,''));
  normalized_world text := left(btrim(coalesce(p_world,'unknown')),80);
  recent_count integer;
  queue_id uuid;
begin
  if p_user_id is null or p_minecraft_uuid is null
     or normalized_nickname='' or char_length(normalized_nickname)>64 then
    raise exception 'BRIDGE_IDENTITY_REQUIRED';
  end if;

  normalized_message := btrim(regexp_replace(coalesce(p_message,''),'[[:cntrl:]]',' ','g'));
  if normalized_message='' or char_length(normalized_message)>500 then
    raise exception 'BRIDGE_INVALID_MESSAGE';
  end if;

  select u.id into identity_id
  from public.users u
  where u.id=p_user_id
    and u.deleted_at is null
    and lower(trim(u.minecraft_nickname))=lower(normalized_nickname)
    and u.minecraft_uuid=p_minecraft_uuid
  for key share;
  if identity_id is null then raise exception 'BRIDGE_IDENTITY_MISMATCH'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mc-chat-bridge:'||identity_id::text,0)
  );
  select count(*) into recent_count
  from public.minecraft_chat_bridge_queue q
  where q.direction='TO_TELEGRAM'
    and q.actor_user_id=identity_id
    and q.created_at > now()-interval '10 seconds';
  if recent_count>=6 then raise exception 'BRIDGE_RATE_LIMITED'; end if;

  insert into public.minecraft_chat_bridge_queue(
    direction,actor_user_id,minecraft_uuid,minecraft_nickname,minecraft_world,message
  )
  values(
    'TO_TELEGRAM',identity_id,p_minecraft_uuid,normalized_nickname,
    coalesce(nullif(normalized_world,''),'unknown'),normalized_message
  )
  returning id into queue_id;

  return json_build_object('success',true,'id',queue_id);
end;
$function$;

create or replace function public.bot_bridge_enqueue_from_telegram(
  p_chat_id bigint,
  p_message_id bigint,
  p_telegram_user_id bigint,
  p_sender_name text,
  p_message text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  configured_chat_id bigint;
  linked_user_id uuid;
  normalized_sender text := left(btrim(regexp_replace(coalesce(p_sender_name,''),'[[:cntrl:]]',' ','g')),128);
  normalized_message text;
  recent_count integer;
  queue_id uuid;
  was_duplicate boolean := false;
begin
  if p_chat_id is null or p_message_id is null or p_telegram_user_id is null
     or normalized_sender='' then
    raise exception 'BRIDGE_TELEGRAM_IDENTITY_REQUIRED';
  end if;

  configured_chat_id := public.bot_get_community_chat_id();
  if p_chat_id is distinct from configured_chat_id then
    raise exception 'BRIDGE_CHAT_NOT_ALLOWED';
  end if;

  normalized_message := btrim(regexp_replace(coalesce(p_message,''),'[[:cntrl:]]',' ','g'));
  if normalized_message='' or char_length(normalized_message)>500 then
    raise exception 'BRIDGE_INVALID_MESSAGE';
  end if;
  if left(normalized_message,1) in ('/','+','-') then
    raise exception 'BRIDGE_COMMAND_BLOCKED';
  end if;

  select u.id into linked_user_id
  from public.users u
  where u.telegram_id=p_telegram_user_id and u.deleted_at is null
  limit 1;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('tg-chat-bridge:'||p_telegram_user_id::text,0)
  );
  select count(*) into recent_count
  from public.minecraft_chat_bridge_queue q
  where q.direction='TO_MINECRAFT'
    and q.telegram_user_id=p_telegram_user_id
    and q.created_at > now()-interval '10 seconds';
  if recent_count>=6 then raise exception 'BRIDGE_RATE_LIMITED'; end if;

  insert into public.minecraft_chat_bridge_queue(
    direction,actor_user_id,telegram_chat_id,telegram_message_id,
    telegram_user_id,telegram_sender_name,message
  )
  values(
    'TO_MINECRAFT',linked_user_id,p_chat_id,p_message_id,
    p_telegram_user_id,normalized_sender,normalized_message
  )
  on conflict (telegram_chat_id,telegram_message_id) do nothing
  returning id into queue_id;

  if queue_id is null then
    was_duplicate := true;
    select q.id into queue_id
    from public.minecraft_chat_bridge_queue q
    where q.telegram_chat_id=p_chat_id and q.telegram_message_id=p_message_id
    limit 1;
  end if;

  return json_build_object('success',true,'id',queue_id,'duplicate',was_duplicate);
end;
$function$;

create or replace function public.mc_bridge_claim_for_telegram(p_limit integer default 20)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  pending json;
  limit_rows integer := greatest(1,least(coalesce(p_limit,20),100));
begin
  update public.minecraft_chat_bridge_queue q
  set status='FAILED',claimed_at=null,lease_token=null,updated_at=now(),last_error='MESSAGE_EXPIRED'
  where q.direction='TO_TELEGRAM'
    and q.status in ('PENDING','PROCESSING')
    and q.created_at < now()-interval '15 minutes';

  update public.minecraft_chat_bridge_queue q
  set status=case when q.attempts>=8 then 'FAILED' else 'PENDING' end,
      claimed_at=null,lease_token=null,updated_at=now(),
      last_error=case when q.attempts>=8 then coalesce(q.last_error,'LEASE_EXPIRED_AFTER_MAX_ATTEMPTS') else q.last_error end
  where q.direction='TO_TELEGRAM'
    and q.status='PROCESSING'
    and q.claimed_at < now()-interval '5 minutes';

  with candidates as (
    select q.id
    from public.minecraft_chat_bridge_queue q
    where q.direction='TO_TELEGRAM'
      and q.status='PENDING'
      and q.available_at<=now()
      and q.attempts<8
    order by q.created_at asc
    limit limit_rows
    for update skip locked
  ),
  claimed as (
    update public.minecraft_chat_bridge_queue q
    set status='PROCESSING',attempts=q.attempts+1,claimed_at=now(),
        lease_token=pg_catalog.gen_random_uuid(),updated_at=now()
    from candidates c
    where q.id=c.id
    returning q.id,q.lease_token,q.minecraft_nickname,q.minecraft_world,q.message,q.created_at
  )
  select coalesce(json_agg(json_build_object(
    'id',c.id,'lease_token',c.lease_token,
    'minecraft_nickname',c.minecraft_nickname,
    'minecraft_world',c.minecraft_world,'message',c.message,'created_at',c.created_at
  ) order by c.created_at asc),'[]'::json)
  into pending
  from claimed c;

  return json_build_object('data',pending,'chat_id',public.bot_get_community_chat_id());
end;
$function$;

create or replace function public.mc_bridge_claim_for_minecraft(p_limit integer default 20)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  pending json;
  limit_rows integer := greatest(1,least(coalesce(p_limit,20),100));
begin
  update public.minecraft_chat_bridge_queue q
  set status='FAILED',claimed_at=null,lease_token=null,updated_at=now(),last_error='MESSAGE_EXPIRED'
  where q.direction='TO_MINECRAFT'
    and q.status in ('PENDING','PROCESSING')
    and q.created_at < now()-interval '15 minutes';

  update public.minecraft_chat_bridge_queue q
  set status=case when q.attempts>=8 then 'FAILED' else 'PENDING' end,
      claimed_at=null,lease_token=null,updated_at=now(),
      last_error=case when q.attempts>=8 then coalesce(q.last_error,'LEASE_EXPIRED_AFTER_MAX_ATTEMPTS') else q.last_error end
  where q.direction='TO_MINECRAFT'
    and q.status='PROCESSING'
    and q.claimed_at < now()-interval '5 minutes';

  with candidates as (
    select q.id
    from public.minecraft_chat_bridge_queue q
    where q.direction='TO_MINECRAFT'
      and q.status='PENDING'
      and q.available_at<=now()
      and q.attempts<8
    order by q.created_at asc
    limit limit_rows
    for update skip locked
  ),
  claimed as (
    update public.minecraft_chat_bridge_queue q
    set status='PROCESSING',attempts=q.attempts+1,claimed_at=now(),
        lease_token=pg_catalog.gen_random_uuid(),updated_at=now()
    from candidates c
    where q.id=c.id
    returning q.id,q.lease_token,q.telegram_sender_name,q.message,q.created_at
  )
  select coalesce(json_agg(json_build_object(
    'id',c.id,'lease_token',c.lease_token,
    'telegram_sender_name',c.telegram_sender_name,
    'message',c.message,'created_at',c.created_at
  ) order by c.created_at asc),'[]'::json)
  into pending
  from claimed c;

  return json_build_object('data',pending);
end;
$function$;

-- Replace the unsafe four-argument finalizer with a claim-token-aware variant.
revoke all on function public.mc_bridge_finish_message(uuid,text,text,integer)
  from public,anon,authenticated,service_role;

create function public.mc_bridge_finish_message(
  p_message_id uuid,
  p_lease_token uuid,
  p_status text,
  p_error text default null,
  p_retry_after_seconds integer default 5
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  current_row public.minecraft_chat_bridge_queue%rowtype;
  next_status text := upper(trim(coalesce(p_status,'')));
begin
  if next_status not in ('DELIVERED','RETRY','FAILED') then
    raise exception 'BRIDGE_INVALID_FINISH_STATUS';
  end if;
  if p_lease_token is null then raise exception 'BRIDGE_LEASE_TOKEN_REQUIRED'; end if;

  select * into current_row
  from public.minecraft_chat_bridge_queue
  where id=p_message_id
  for update;
  if current_row.id is null then raise exception 'BRIDGE_MESSAGE_NOT_FOUND'; end if;

  if current_row.status='DELIVERED' and next_status='DELIVERED' then
    return json_build_object('success',true,'status','DELIVERED','already_delivered',true);
  end if;
  if current_row.status<>'PROCESSING'
     or current_row.lease_token is distinct from p_lease_token then
    raise exception 'BRIDGE_LEASE_NOT_HELD';
  end if;

  if next_status='DELIVERED' then
    update public.minecraft_chat_bridge_queue
    set status='DELIVERED',claimed_at=null,lease_token=null,
        delivered_at=now(),updated_at=now(),last_error=null
    where id=p_message_id;
    return json_build_object('success',true,'status','DELIVERED');
  end if;

  if next_status='FAILED' or current_row.attempts>=8 then
    update public.minecraft_chat_bridge_queue
    set status='FAILED',claimed_at=null,lease_token=null,updated_at=now(),
        last_error=left(coalesce(p_error,'BRIDGE_DELIVERY_FAILED'),500)
    where id=p_message_id;
    return json_build_object('success',true,'status','FAILED');
  end if;

  update public.minecraft_chat_bridge_queue
  set status='PENDING',claimed_at=null,lease_token=null,updated_at=now(),
      available_at=now()+make_interval(secs=>greatest(1,least(coalesce(p_retry_after_seconds,5),600))),
      last_error=left(coalesce(p_error,'BRIDGE_DELIVERY_RETRY'),500)
  where id=p_message_id;

  return json_build_object('success',true,'status','PENDING');
end;
$function$;

revoke all on function public.mc_bridge_enqueue_from_minecraft(uuid,uuid,text,text,text)
  from public,anon,authenticated;
revoke all on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text)
  from public,anon,authenticated;
revoke all on function public.mc_bridge_claim_for_telegram(integer)
  from public,anon,authenticated;
revoke all on function public.mc_bridge_claim_for_minecraft(integer)
  from public,anon,authenticated;
revoke all on function public.mc_bridge_finish_message(uuid,uuid,text,text,integer)
  from public,anon,authenticated;

grant execute on function public.mc_bridge_enqueue_from_minecraft(uuid,uuid,text,text,text) to service_role;
grant execute on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text) to service_role;
grant execute on function public.mc_bridge_claim_for_telegram(integer) to service_role;
grant execute on function public.mc_bridge_claim_for_minecraft(integer) to service_role;
grant execute on function public.mc_bridge_finish_message(uuid,uuid,text,text,integer) to service_role;
