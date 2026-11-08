-- PRISMA: atomically claim users due for the daily group onboarding reminder.
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
      and u.bot_started_at is null
      and coalesce(u.onboarding_last_notified_at,to_timestamp(0)) <= now() - interval '24 hours'
      and not exists (select 1 from public.admins a where a.user_id=u.id)
    order by coalesce(u.community_last_seen_at,u.community_first_seen_at) desc
    limit greatest(1,least(coalesce(p_limit,20),100))
    for update skip locked
  ),
  claimed as (
    update public.users u
    set onboarding_last_notified_at=now(), updated_at=now()
    from due
    where u.id=due.id
    returning u.id,u.telegram_id,u.telegram_username,u.first_name,u.full_name
  )
  select coalesce(
    json_agg(json_build_object(
      'id',id,'telegram_id',telegram_id,'telegram_username',telegram_username,
      'first_name',first_name,'full_name',full_name
    )),
    '[]'::json
  ) into result
  from claimed;
  return result;
end;
$$;

revoke all on function public.bot_claim_onboarding_reminders(integer) from public,anon,authenticated;
grant execute on function public.bot_claim_onboarding_reminders(integer) to service_role;
