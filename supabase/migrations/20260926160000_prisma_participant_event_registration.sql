-- Participant event registration gateways. Actor identity comes from auth.uid().

create or replace function private.prisma_participant_register_event(p_user_id uuid,p_event_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare e public.events%rowtype; already boolean; count_now integer;
begin
  perform private.prisma_participant_require_access(p_user_id);
  select * into e from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if e.status not in ('scheduled','live','published','registration','open','active') then
    raise exception 'EVENT_NOT_OPEN';
  end if;
  if e.registration_deadline is not null and e.registration_deadline<=now() then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  select exists(select 1 from public.event_participants ep where ep.event_id=p_event_id and ep.user_id=p_user_id) into already;
  if already then return jsonb_build_object('success',true,'duplicate',true,'registered',true,'event_id',p_event_id); end if;

  if e.max_participants is not null then
    select count(*) into count_now from public.event_participants ep where ep.event_id=p_event_id;
    if count_now>=e.max_participants then raise exception 'EVENT_FULL'; end if;
  end if;

  insert into public.event_participants(event_id,user_id) values(p_event_id,p_user_id);
  return jsonb_build_object('success',true,'duplicate',false,'registered',true,'event_id',p_event_id);
end;
$function$;

create or replace function public.participant_register_event(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_register_event(uid,p_event_id);
end;
$function$;

create or replace function private.prisma_participant_unregister_event(p_user_id uuid,p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  delete from public.event_participants ep where ep.event_id=p_event_id and ep.user_id=p_user_id;
  if not found then raise exception 'REGISTRATION_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'registered',false,'event_id',p_event_id);
end;
$function$;

create or replace function public.participant_unregister_event(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_unregister_event(uid,p_event_id);
end;
$function$;

revoke all on function public.participant_register_event(uuid) from public,anon;
grant execute on function public.participant_register_event(uuid) to authenticated;
revoke all on function public.participant_unregister_event(uuid) from public,anon;
grant execute on function public.participant_unregister_event(uuid) to authenticated;
