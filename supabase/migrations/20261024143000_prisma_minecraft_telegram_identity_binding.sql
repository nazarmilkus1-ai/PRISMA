-- PRISMA 2.1.0: require the existing PRISMA identity binding in both bridge directions.
-- Forward-only hardening. This migration is not applied to production by the repository change.
-- A Telegram display name is never treated as a Minecraft identity.

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

  -- The UUID and current nick must match the active profile, which must also
  -- have a Telegram identity bound. FOR SHARE prevents concurrent unbinding
  -- from racing the enqueue transaction.
  select u.id into identity_id
  from public.users u
  where u.id=p_user_id
    and u.deleted_at is null
    and u.telegram_id is not null
    and lower(trim(u.minecraft_nickname))=lower(normalized_nickname)
    and u.minecraft_uuid=p_minecraft_uuid
  FOR SHARE;
  if identity_id is null then raise exception 'BRIDGE_IDENTITY_MISMATCH_OR_UNBOUND'; end if;

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

  -- Match by Telegram's numeric user ID, not by the display name supplied in
  -- the update. Only an active profile already bound to a Minecraft UUID may
  -- publish into the game chat.
  select u.id into linked_user_id
  from public.users u
  where u.telegram_id=p_telegram_user_id
    and u.deleted_at is null
    and u.minecraft_uuid is not null
    and nullif(btrim(u.minecraft_nickname),'') is not null
  FOR SHARE;
  if linked_user_id is null then raise exception 'BRIDGE_TELEGRAM_IDENTITY_UNBOUND'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('tg-chat-bridge:'||p_telegram_user_id::text,0)
  );

  -- A Telegram retry for an already-seen update remains idempotent and must
  -- not consume another rate-limit slot.
  select q.id into queue_id
  from public.minecraft_chat_bridge_queue q
  where q.telegram_chat_id=p_chat_id and q.telegram_message_id=p_message_id
  limit 1;
  if queue_id is not null then
    return json_build_object('success',true,'id',queue_id,'duplicate',true);
  end if;

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

-- Keep all bridge RPCs unavailable to client roles; only server-side workers
-- using the Supabase service role can enqueue, claim or finish bridge messages.
revoke all on function public.mc_bridge_enqueue_from_minecraft(uuid,uuid,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text)
  from public,anon,authenticated,service_role;

grant execute on function public.mc_bridge_enqueue_from_minecraft(uuid,uuid,text,text,text)
  to service_role;
grant execute on function public.bot_bridge_enqueue_from_telegram(bigint,bigint,bigint,text,text)
  to service_role;
