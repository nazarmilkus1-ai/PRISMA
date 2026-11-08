alter table public.users
  add column if not exists community_is_member boolean not null default false,
  add column if not exists community_joined_at timestamptz,
  add column if not exists community_left_at timestamptz;

create index if not exists users_community_onboarding_idx
  on public.users (community_is_member, bot_started_at, onboarding_last_notified_at)
  where deleted_at is null;

create or replace function public.bot_set_community_membership(
  p_tg_id bigint,
  p_username text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_full_name text default null,
  p_is_member boolean default true
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  uid uuid;
  now_ts timestamptz := now();
  started_at timestamptz;
  was_created boolean := false;
begin
  if p_tg_id is null then
    raise exception 'INVALID_TELEGRAM_ID';
  end if;

  select id, bot_started_at
    into uid, started_at
  from public.users
  where telegram_id = p_tg_id
  for update;

  if uid is null then
    insert into public.users(
      telegram_id,
      telegram_username,
      first_name,
      last_name,
      full_name,
      status,
      is_whitelisted,
      community_first_seen_at,
      community_last_seen_at,
      community_is_member,
      community_joined_at,
      community_left_at
    ) values (
      p_tg_id,
      nullif(trim(p_username), ''),
      nullif(trim(p_first_name), ''),
      nullif(trim(p_last_name), ''),
      nullif(trim(p_full_name), ''),
      'PENDING',
      false,
      case when p_is_member then now_ts else null end,
      case when p_is_member then now_ts else null end,
      coalesce(p_is_member, false),
      case when p_is_member then now_ts else null end,
      case when p_is_member then null else now_ts end
    )
    returning id, bot_started_at into uid, started_at;
    was_created := true;
  else
    update public.users
    set telegram_username = coalesce(nullif(trim(p_username), ''), telegram_username),
        first_name = coalesce(nullif(trim(p_first_name), ''), first_name),
        last_name = coalesce(nullif(trim(p_last_name), ''), last_name),
        full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
        community_first_seen_at = case
          when p_is_member then coalesce(community_first_seen_at, now_ts)
          else community_first_seen_at
        end,
        community_last_seen_at = case
          when p_is_member then now_ts
          else community_last_seen_at
        end,
        community_is_member = coalesce(p_is_member, false),
        community_joined_at = case
          when p_is_member then now_ts
          else community_joined_at
        end,
        community_left_at = case
          when p_is_member then null
          else now_ts
        end,
        updated_at = now_ts
    where id = uid;
  end if;

  return json_build_object(
    'success', true,
    'created', was_created,
    'user_id', uid,
    'is_member', coalesce(p_is_member, false),
    'bot_started', started_at is not null
  );
end;
$$;

revoke all on function public.bot_set_community_membership(bigint,text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.bot_set_community_membership(bigint,text,text,text,text,boolean) to service_role;

create or replace function public.bot_claim_onboarding_reminders(
  p_limit integer default 20
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare result json;
begin
  with due as (
    select u.id
    from public.users u
    where u.deleted_at is null
      and u.community_first_seen_at is not null
      and u.community_is_member = true
      and u.bot_started_at is null
      and coalesce(u.onboarding_last_notified_at, to_timestamp(0)) <= now() - interval '24 hours'
      and not exists (select 1 from public.admins a where a.user_id = u.id)
    order by coalesce(u.community_last_seen_at, u.community_first_seen_at) desc
    limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked
  ),
  claimed as (
    update public.users u
    set onboarding_last_notified_at = now(), updated_at = now()
    from due
    where u.id = due.id
    returning u.id, u.telegram_id, u.telegram_username, u.first_name, u.full_name
  )
  select coalesce(
    json_agg(json_build_object(
      'id', id,
      'telegram_id', telegram_id,
      'telegram_username', telegram_username,
      'first_name', first_name,
      'full_name', full_name
    )),
    '[]'::json
  ) into result
  from claimed;

  return result;
end;
$$;

revoke all on function public.bot_claim_onboarding_reminders(integer) from public, anon, authenticated;
grant execute on function public.bot_claim_onboarding_reminders(integer) to service_role;
