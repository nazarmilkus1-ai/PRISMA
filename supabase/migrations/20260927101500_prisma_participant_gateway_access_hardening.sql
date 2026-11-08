create or replace function public.participant_cancel_clan_war(p_war_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_cancel_clan_war(uid,p_war_id);
end;
$function$;

create or replace function public.participant_create_clan_war(p_target text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_create_clan_war(uid,p_target);
end;
$function$;

create or replace function public.participant_finish_clan_war(
  p_war_id uuid,
  p_score_a integer,
  p_score_b integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_finish_clan_war(uid,p_war_id,p_score_a,p_score_b);
end;
$function$;

create or replace function public.participant_respond_clan_war(
  p_war_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_respond_clan_war(uid,p_war_id,p_action);
end;
$function$;

create or replace function public.participant_start_clan_war(p_war_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_start_clan_war(uid,p_war_id);
end;
$function$;

create or replace function public.participant_mark_notification_read(p_notification_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_mark_notification_read(uid,p_notification_id);
end;
$function$;

create or replace function public.participant_update_notification_preference(
  p_key text,
  p_value boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_participant_update_notification_preference(uid,p_key,p_value);
end;
$function$;

create or replace function public.participant_create_report(
  p_type text,
  p_target_nickname text,
  p_description text
)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return private.prisma_create_report(uid,p_type,p_target_nickname,p_description);
end;
$function$;

create or replace function public.participant_update_profile(
  p_full_name text,
  p_locale text,
  p_profile_links jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  uid uuid;
  clean_name text:=trim(coalesce(p_full_name,''));
  clean_locale text:=lower(trim(coalesce(p_locale,'ru')));
  links jsonb:=coalesce(p_profile_links,'{}'::jsonb);
  key_name text;
  key_value text;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);

  if char_length(clean_name) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if clean_locale not in ('ru','uk','en') then raise exception 'INVALID_LOCALE'; end if;
  if jsonb_typeof(links)<>'object' then raise exception 'INVALID_PROFILE_LINKS'; end if;

  for key_name,key_value in
    select e.key,e.value #>> '{}'
    from jsonb_each(links) e
  loop
    if key_name not in ('website','discord','youtube','telegram') then
      raise exception 'INVALID_PROFILE_LINK_KEY';
    end if;
    if key_value is null or key_value='' then continue; end if;
    if char_length(key_value)>300 or key_value !~* '^https://[^[:space:]]+$' then
      raise exception 'INVALID_PROFILE_LINK_URL';
    end if;
  end loop;

  update public.users
  set full_name=clean_name,
      locale=clean_locale,
      profile_links=(
        select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb)
        from jsonb_each(links) e
        where e.key in ('website','discord','youtube','telegram')
          and jsonb_typeof(e.value)='string'
          and char_length(trim(e.value #>> '{}'))>0
      ),
      updated_at=now()
  where id=uid;

  return jsonb_build_object('success',true,'user_id',uid);
end;
$function$;

grant execute on function public.participant_cancel_clan_war(uuid) to authenticated;
grant execute on function public.participant_create_clan_war(text) to authenticated;
grant execute on function public.participant_finish_clan_war(uuid,integer,integer) to authenticated;
grant execute on function public.participant_respond_clan_war(uuid,text) to authenticated;
grant execute on function public.participant_start_clan_war(uuid) to authenticated;
grant execute on function public.participant_mark_notification_read(uuid) to authenticated;
grant execute on function public.participant_update_notification_preference(text,boolean) to authenticated;
grant execute on function public.participant_create_report(text,text,text) to authenticated;
grant execute on function public.participant_update_profile(text,text,jsonb) to authenticated;
revoke execute on function public.participant_cancel_clan_war(uuid) from anon;
revoke execute on function public.participant_create_clan_war(text) from anon;
revoke execute on function public.participant_finish_clan_war(uuid,integer,integer) from anon;
revoke execute on function public.participant_respond_clan_war(uuid,text) from anon;
revoke execute on function public.participant_start_clan_war(uuid) from anon;
revoke execute on function public.participant_mark_notification_read(uuid) from anon;
revoke execute on function public.participant_update_notification_preference(text,boolean) from anon;
revoke execute on function public.participant_create_report(text,text,text) from anon;
revoke execute on function public.participant_update_profile(text,text,jsonb) from anon;