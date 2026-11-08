-- Prevent duplicate onboarding reminders after a user joins the community.
-- A join counts as the daily onboarding notification for users who have not
-- started the bot and do not have a pending/accepted application.
create or replace function public.bot_set_community_membership(
  p_tg_id bigint,
  p_username text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_full_name text default null,
  p_is_member boolean default true
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  uid uuid;
  now_ts timestamptz := now();
  started_at timestamptz;
  previous_is_member boolean;
  was_created boolean := false;
  has_application boolean := false;
  latest_application_status text;
  joined_now boolean := false;
begin
  if p_tg_id is null then
    raise exception 'INVALID_TELEGRAM_ID';
  end if;

  select
    u.id,
    u.bot_started_at,
    coalesce(u.community_is_member, false)
  into uid, started_at, previous_is_member
  from public.users u
  where u.telegram_id = p_tg_id
  for update;

  select
    exists (
      select 1
      from public.applications a
      where a.user_id = uid
    ),
    upper(a.status::text)
  into has_application, latest_application_status
  from public.applications a
  where a.user_id = uid
  order by a.created_at desc, a.id desc
  limit 1;

  if uid is null then
    has_application := false;
    latest_application_status := null;

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
      community_left_at,
      onboarding_last_notified_at
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
      case when p_is_member then null else now_ts end,
      case when p_is_member then now_ts else null end
    )
    returning id, bot_started_at into uid, started_at;

    was_created := true;
    joined_now := coalesce(p_is_member, false);
  else
    joined_now := coalesce(p_is_member, false) and not previous_is_member;

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
        onboarding_last_notified_at = case
          when joined_now
            and not has_application
            and started_at is null
            then now_ts
          else onboarding_last_notified_at
        end,
        updated_at = now_ts
    where id = uid;
  end if;

  return json_build_object(
    'success', true,
    'created', was_created,
    'user_id', uid,
    'is_member', coalesce(p_is_member, false),
    'joined_now', joined_now,
    'bot_started', started_at is not null,
    'has_application', has_application,
    'application_status', latest_application_status
  );
end;
$function$;
