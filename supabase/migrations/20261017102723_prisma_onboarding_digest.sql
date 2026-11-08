-- PRISMA: aggregate onboarding reminders and staff-triggered invitation lists.
-- Candidate profile data is returned to the server-side bot only.

create or replace function public.bot_claim_onboarding_digest(
  p_limit integer default 100,
  p_force boolean default false
) returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result json;
begin
  with due as (
    select u.id
    from public.users as u
    where u.deleted_at is null
      and u.community_first_seen_at is not null
      and coalesce(u.community_is_member, false)
      and not coalesce(u.is_whitelisted, false)
      and upper(u.status::text) not in ('ACCEPTED', 'REJECTED')
      and not coalesce(u.is_banned, false)
      and not exists (
        select 1 from public.admins as a where a.user_id = u.id
      )
      and not exists (
        select 1 from public.applications as a where a.user_id = u.id
      )
      and (
        p_force
        or coalesce(u.onboarding_last_notified_at, to_timestamp(0))
          <= now() - interval '24 hours'
      )
    order by coalesce(u.community_last_seen_at, u.community_first_seen_at) desc
    limit greatest(1, least(coalesce(p_limit, 100), 1000))
    for update skip locked
  ),
  claimed as (
    update public.users as u
    set onboarding_last_notified_at = now(),
        updated_at = now()
    from due
    where u.id = due.id
    returning
      u.id,
      u.telegram_id,
      u.telegram_username,
      u.first_name,
      u.full_name,
      u.bot_started_at,
      u.community_first_seen_at,
      u.community_last_seen_at
  )
  select coalesce(
    json_agg(
      json_build_object(
        'id', id,
        'telegram_id', telegram_id,
        'telegram_username', telegram_username,
        'first_name', first_name,
        'full_name', full_name,
        'onboarding_stage',
          case
            when bot_started_at is null then 'NOT_OPENED'
            else 'OPENED_NO_APPLICATION'
          end
      )
      order by
        case when bot_started_at is null then 0 else 1 end,
        coalesce(community_last_seen_at, community_first_seen_at) desc
    ),
    '[]'::json
  )
  into result
  from claimed;

  return result;
end;
$function$;

revoke all on function public.bot_claim_onboarding_digest(integer, boolean)
  from public, anon, authenticated;
grant execute on function public.bot_claim_onboarding_digest(integer, boolean)
  to service_role;
