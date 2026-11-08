-- PRISMA v2: current-user gateway must not expose the internal Auth UUID.
create or replace function public.participant_get_current_user()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(
  (
    select jsonb_build_object(
      'id', u.id,
      'telegram_id', u.telegram_id,
      'telegram_username', u.telegram_username,
      'first_name', u.first_name,
      'last_name', u.last_name,
      'full_name', u.full_name,
      'age', u.age,
      'minecraft_nickname', u.minecraft_nickname,
      'platform', u.platform,
      'status', u.status,
      'is_whitelisted', u.is_whitelisted,
      'is_banned', u.is_banned,
      'ban_reason', u.ban_reason,
      'is_muted', u.is_muted,
      'muted_until', u.muted_until,
      'rating', u.rating,
      'activity_score', u.activity_score,
      'level', u.level,
      'xp', u.xp,
      'last_login_at', u.last_login_at,
      'created_at', u.created_at,
      'clan_id', u.clan_id,
      'locale', u.locale,
      'birth_date', u.birth_date,
      'profile_links', u.profile_links,
      'social_visibility', u.social_visibility
    )
    from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.deleted_at is null
    limit 1
  ),
  null
);
$function$;

revoke execute on function public.participant_get_current_user() from public, anon;
grant execute on function public.participant_get_current_user() to authenticated;
grant execute on function public.participant_get_current_user() to postgres;
