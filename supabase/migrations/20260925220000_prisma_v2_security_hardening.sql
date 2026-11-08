-- PRISMA v2 security hardening.
-- Browser-facing RPC wrappers are invoker functions. Privileged work remains
-- inside the private schema and the wrapper derives identity from auth.uid().
-- Internal/runtime tables are explicitly inaccessible to browser roles.

create or replace function public.participant_create_report(
  p_type text,
  p_target_nickname text,
  p_description text
) returns json
language plpgsql
security invoker
set search_path=''
as $prisma$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_LINKED';
  end if;

  return private.prisma_create_report(
    uid,
    p_type,
    p_target_nickname,
    p_description
  );
end;
$prisma$;

create or replace function public.site_submit_application(
  p_full_name text,
  p_birth_date date,
  p_minecraft_nick text,
  p_platform text,
  p_goal text,
  p_about text,
  p_discovery_source text
) returns json
language plpgsql
security invoker
set search_path=''
as $prisma$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_LINKED';
  end if;

  return private.prisma_create_application(
    uid,
    p_full_name,
    p_birth_date,
    p_minecraft_nick,
    p_platform,
    p_goal,
    p_about,
    p_discovery_source
  );
end;
$prisma$;

create or replace function public.staff_decide_application(
  p_application_id uuid,
  p_action text,
  p_reason text default null
) returns json
language plpgsql
security invoker
set search_path=''
as $prisma$
declare
  actor_user_id uuid;
begin
  select u.id into actor_user_id
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1;

  if actor_user_id is null then
    raise exception 'STAFF_IDENTITY_NOT_FOUND';
  end if;

  return private.prisma_decide_application(
    p_application_id,
    actor_user_id,
    p_action,
    p_reason
  );
end;
$prisma$;

create or replace function public.staff_update_report(
  p_report_id uuid,
  p_status text,
  p_internal_notes text default null,
  p_assigned_to uuid default null,
  p_involved_players jsonb default null
) returns json
language plpgsql
security invoker
set search_path=''
as $prisma$
declare
  actor_user_id uuid;
begin
  select u.id into actor_user_id
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1;

  if actor_user_id is null then
    raise exception 'STAFF_IDENTITY_NOT_FOUND';
  end if;

  return private.prisma_update_report(
    p_report_id,
    actor_user_id,
    p_status,
    p_internal_notes,
    p_assigned_to,
    p_involved_players
  );
end;
$prisma$;

revoke all on function public.participant_create_report(text,text,text) from public, anon;
revoke all on function public.site_submit_application(text,date,text,text,text,text,text) from public, anon;
revoke all on function public.staff_decide_application(uuid,text,text) from public, anon;
revoke all on function public.staff_update_report(uuid,text,text,uuid,jsonb) from public, anon;

grant execute on function public.participant_create_report(text,text,text) to authenticated;
grant execute on function public.site_submit_application(text,date,text,text,text,text,text) to authenticated;
grant execute on function public.staff_decide_application(uuid,text,text) to authenticated;
grant execute on function public.staff_update_report(uuid,text,text,uuid,jsonb) to authenticated;

grant usage on schema private to authenticated;
grant execute on function private.prisma_create_report(uuid,text,text,text) to authenticated;
grant execute on function private.prisma_create_application(uuid,text,date,text,text,text,text,text) to authenticated;
grant execute on function private.prisma_decide_application(uuid,uuid,text,text) to authenticated;
grant execute on function private.prisma_update_report(uuid,uuid,text,text,uuid,jsonb) to authenticated;

revoke all on table
  public.activity_events,
  public.bot_sessions,
  public.broadcasts,
  public.clan_villages,
  public.iris_chat_stats_archive,
  public.iris_clan_import_archive,
  public.iris_inactive_snapshot,
  public.iris_marriage_import_archive,
  public.iris_nickname_import_archive,
  public.login_history,
  public.marriage_requests,
  public.marriages,
  public.punishment_appeals,
  public.relationship_requests,
  public.relationships,
  public.scheduled_jobs,
  public.telegram_chat_activity,
  public.telegram_chat_activity_legacy,
  public.telegram_chat_daily_snapshot,
  public.telegram_chat_history_imports,
  public.telegram_chat_import_state,
  public.telegram_chat_import_user_baseline,
  public.telegram_chat_profile_snapshot
from anon, authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'activity_events',
    'bot_sessions',
    'broadcasts',
    'clan_villages',
    'iris_chat_stats_archive',
    'iris_clan_import_archive',
    'iris_inactive_snapshot',
    'iris_marriage_import_archive',
    'iris_nickname_import_archive',
    'login_history',
    'marriage_requests',
    'marriages',
    'punishment_appeals',
    'relationship_requests',
    'relationships',
    'scheduled_jobs',
    'telegram_chat_activity',
    'telegram_chat_activity_legacy',
    'telegram_chat_daily_snapshot',
    'telegram_chat_history_imports',
    'telegram_chat_import_state',
    'telegram_chat_import_user_baseline',
    'telegram_chat_profile_snapshot'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'prisma_deny_browser_access', table_name);
    execute format(
      'create policy %I on public.%I for all to anon, authenticated using (false) with check (false)',
      'prisma_deny_browser_access',
      table_name
    );
  end loop;
end
$$;