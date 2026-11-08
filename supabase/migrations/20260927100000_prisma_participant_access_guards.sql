create or replace function public.participant_cancel_clan_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_cancel_clan_invite(uid,p_invite_id);
end;
$function$;

create or replace function public.participant_clan_invite(p_target_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_invite_player(uid,p_target_nickname);
end;
$function$;

create or replace function public.participant_clan_invite_accept(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_accept_clan_invite(uid,p_invite_id);
end;
$function$;

create or replace function public.participant_clan_invite_decline(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_decline_clan_invite(uid,p_invite_id);
end;
$function$;

create or replace function public.participant_create_village(
  p_name text,
  p_world text,
  p_x double precision,
  p_y double precision,
  p_z double precision,
  p_radius integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_create_village(uid,p_name,p_world,p_x,p_y,p_z,p_radius);
end;
$function$;

create or replace function public.participant_delete_village(p_village_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_delete_village(uid,p_village_id);
end;
$function$;

create or replace function public.participant_set_clan_role(
  p_target_nickname text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  return public.mc_set_clan_role(uid,p_target_nickname,p_role);
end;
$function$;

create or replace function public.participant_vote_poll(
  p_poll_id uuid,
  p_option_id uuid
)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare uid uuid; tg_id bigint;
begin
  select u.id,u.telegram_id into uid,tg_id
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  perform private.prisma_participant_require_access(uid);
  if tg_id is null then raise exception 'TELEGRAM_NOT_LINKED'; end if;
  return public.bot_vote_poll(p_poll_id,p_option_id,tg_id);
end;
$function$;

grant execute on function public.participant_cancel_clan_invite(uuid) to authenticated;
grant execute on function public.participant_clan_invite(text) to authenticated;
grant execute on function public.participant_clan_invite_accept(uuid) to authenticated;
grant execute on function public.participant_clan_invite_decline(uuid) to authenticated;
grant execute on function public.participant_create_village(text,text,double precision,double precision,double precision,integer) to authenticated;
grant execute on function public.participant_delete_village(uuid) to authenticated;
grant execute on function public.participant_set_clan_role(text,text) to authenticated;
grant execute on function public.participant_vote_poll(uuid,uuid) to authenticated;
revoke execute on function public.participant_cancel_clan_invite(uuid) from anon;
revoke execute on function public.participant_clan_invite(text) from anon;
revoke execute on function public.participant_clan_invite_accept(uuid) from anon;
revoke execute on function public.participant_clan_invite_decline(uuid) from anon;
revoke execute on function public.participant_create_village(text,text,double precision,double precision,double precision,integer) from anon;
revoke execute on function public.participant_delete_village(uuid) from anon;
revoke execute on function public.participant_set_clan_role(text,text) from anon;
revoke execute on function public.participant_vote_poll(uuid,uuid) from anon;