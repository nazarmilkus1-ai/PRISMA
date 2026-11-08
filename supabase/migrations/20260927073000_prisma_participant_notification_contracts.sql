alter table public.notification_preferences
  add constraint notification_preferences_user_id_key unique (user_id);

create or replace function private.prisma_participant_update_notification_preference(
  p_user_id uuid,
  p_key text,
  p_value boolean
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_key text := lower(trim(coalesce(p_key,'')));
begin
  if not exists (
    select 1 from public.users u
    where u.id=p_user_id
      and u.deleted_at is null
  ) then
    raise exception 'USER_NOT_LINKED';
  end if;

  if v_key not in ('news','events','server_status','clan_news','social','battles','market','moderation','polls') then
    raise exception 'INVALID_PREFERENCE';
  end if;

  insert into public.notification_preferences(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  update public.notification_preferences
  set
    news=case when v_key='news' then p_value else news end,
    events=case when v_key='events' then p_value else events end,
    server_status=case when v_key='server_status' then p_value else server_status end,
    clan_news=case when v_key='clan_news' then p_value else clan_news end,
    social=case when v_key='social' then p_value else social end,
    battles=case when v_key='battles' then p_value else battles end,
    market=case when v_key='market' then p_value else market end,
    moderation=case when v_key='moderation' then p_value else moderation end,
    polls=case when v_key='polls' then p_value else polls end,
    updated_at=now()
  where user_id=p_user_id;

  return jsonb_build_object('success',true,'key',v_key,'value',p_value);
end;
$function$;

create or replace function public.participant_update_notification_preference(
  p_key text,
  p_value boolean
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_update_notification_preference(uid,p_key,p_value);
end;
$function$;

revoke execute on function public.participant_update_notification_preference(text,boolean) from public,anon;
grant execute on function public.participant_update_notification_preference(text,boolean) to authenticated;

create or replace function private.prisma_participant_mark_notification_read(
  p_user_id uuid,
  p_notification_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_updated integer := 0;
begin
  if not exists (
    select 1 from public.users u
    where u.id=p_user_id
      and u.deleted_at is null
  ) then raise exception 'USER_NOT_LINKED'; end if;

  if p_notification_id is null then
    update public.notifications
    set status='read', updated_at=now()
    where user_id=p_user_id and status='sent';
  else
    update public.notifications
    set status='read', updated_at=now()
    where id=p_notification_id and user_id=p_user_id and status='sent';
  end if;

  get diagnostics v_updated = row_count;
  return jsonb_build_object('success',true,'updated',v_updated);
end;
$function$;

create or replace function public.participant_mark_notification_read(
  p_notification_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_mark_notification_read(uid,p_notification_id);
end;
$function$;

revoke execute on function public.participant_mark_notification_read(uuid) from public,anon;
grant execute on function public.participant_mark_notification_read(uuid) to authenticated;
