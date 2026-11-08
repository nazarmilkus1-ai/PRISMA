-- PRISMA v2: authenticated gateways execute under the database owner.
-- Each gateway derives the participant/staff identity from auth.uid().
-- Browser roles retain execute access only to these public gateways.

create or replace function public.participant_create_clan(p_name text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_create_clan(uid,p_name);
end;
$function$;

create or replace function public.participant_get_clan(p_clan_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_clan(uid,p_clan_id);
end;
$function$;

create or replace function public.participant_join_clan(p_clan_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_join_clan(uid,p_clan_id);
end;
$function$;

create or replace function public.participant_leave_clan()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_leave_clan(uid);
end;
$function$;

create or replace function public.participant_list_clans()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_list_clans(uid);
end;
$function$;

create or replace function public.participant_create_report(
  p_type text,p_target_nickname text,p_description text
)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_create_report(uid,p_type,p_target_nickname,p_description);
end;
$function$;

create or replace function public.site_submit_application(
  p_full_name text,p_birth_date date,p_minecraft_nick text,p_platform text,
  p_goal text,p_about text,p_discovery_source text
)
returns json language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_create_application(
    uid,p_full_name,p_birth_date,p_minecraft_nick,p_platform,p_goal,p_about,p_discovery_source
  );
end;
$function$;

create or replace function public.staff_decide_application(
  p_application_id uuid,p_action text,p_reason text default null
)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_user_id uuid;
begin
  select u.id into actor_user_id from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if actor_user_id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;
  return private.prisma_decide_application(p_application_id,actor_user_id,p_action,p_reason);
end;
$function$;

create or replace function public.staff_update_report(
  p_report_id uuid,p_status text,p_internal_notes text default null,
  p_assigned_to uuid default null,p_involved_players jsonb default null
)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_user_id uuid;
begin
  select u.id into actor_user_id from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if actor_user_id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;
  return private.prisma_update_report(
    p_report_id,actor_user_id,p_status,p_internal_notes,p_assigned_to,p_involved_players
  );
end;
$function$;
