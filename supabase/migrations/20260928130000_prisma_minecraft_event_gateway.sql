-- PRISMA v2: canonical Minecraft event write gateways.
-- The Paper plugin must not mutate exposed tables directly.

create or replace function public.mc_record_minecraft_event(
  p_user_id uuid,
  p_event_type text,
  p_nickname text default null,
  p_command text default null,
  p_message text default null,
  p_world text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  event_id uuid;
  v_type text := upper(trim(coalesce(p_event_type,'')));
  v_nick text := nullif(left(trim(coalesce(p_nickname,'')),64),'');
  v_command text := nullif(left(coalesce(p_command,''),512),'');
  v_message text := nullif(left(coalesce(p_message,''),2000),'');
  v_world text := nullif(left(trim(coalesce(p_world,'')),128),'');
begin
  if p_user_id is null then raise exception 'USER_NOT_FOUND'; end if;
  if not exists(select 1 from public.users u where u.id=p_user_id and u.deleted_at is null) then
    raise exception 'USER_NOT_FOUND';
  end if;
  if v_type not in ('JOIN','QUIT','CHAT','COMMAND') then
    raise exception 'INVALID_EVENT_TYPE';
  end if;

  insert into public.minecraft_events(
    user_id,event_type,nickname,command,message,world,metadata
  )
  values(
    p_user_id,v_type,v_nick,v_command,v_message,v_world,coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into event_id;

  update public.users
  set last_seen_at=case
      when v_type <> 'QUIT' then now()
      else last_seen_at
    end,
    updated_at=now()
  where id=p_user_id;

  return jsonb_build_object('success',true,'event_id',event_id,'event_type',v_type);
end;
$function$;

create or replace function public.mc_record_chat_message(
  p_user_id uuid,
  p_message text,
  p_world text default null,
  p_nickname text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  chat_id uuid;
  event_id uuid;
  v_message text := trim(coalesce(p_message,''));
  v_world text := nullif(left(trim(coalesce(p_world,'')),128),'');
  v_nick text := nullif(left(trim(coalesce(p_nickname,'')),64),'');
begin
  if p_user_id is null then raise exception 'USER_NOT_FOUND'; end if;
  if not exists(select 1 from public.users u where u.id=p_user_id and u.deleted_at is null) then
    raise exception 'USER_NOT_FOUND';
  end if;
  if char_length(v_message) < 1 or char_length(v_message) > 2000 then
    raise exception 'INVALID_MESSAGE';
  end if;

  insert into public.chat_logs(user_id,message,world)
  values(p_user_id,v_message,v_world)
  returning id into chat_id;

  insert into public.minecraft_events(
    user_id,event_type,nickname,message,world,metadata
  )
  values(
    p_user_id,'CHAT',v_nick,v_message,v_world,coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into event_id;

  return jsonb_build_object(
    'success',true,
    'chat_log_id',chat_id,
    'event_id',event_id
  );
end;
$function$;

revoke all on function public.mc_record_minecraft_event(uuid,text,text,text,text,text,jsonb)
from public,anon,authenticated;
grant execute on function public.mc_record_minecraft_event(uuid,text,text,text,text,text,jsonb)
to service_role;

revoke all on function public.mc_record_chat_message(uuid,text,text,text,jsonb)
from public,anon,authenticated;
grant execute on function public.mc_record_chat_message(uuid,text,text,text,jsonb)
to service_role;
