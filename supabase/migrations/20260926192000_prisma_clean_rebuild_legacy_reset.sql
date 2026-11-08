-- PRISMA clean rebuild: remove legacy Iris-derived domain data.
-- Current accepted + whitelisted participant rows in public.users are preserved.

update public.users
set clan_id=null, updated_at=now()
where clan_id is not null;

delete from public.timeline_events where clan_id is not null;

delete from public.clan_achievements;
delete from public.clan_activity;
delete from public.clan_alliances;
delete from public.clan_announcements;
delete from public.clan_invitations;
delete from public.clan_messages;
delete from public.clan_villages;
delete from public.clan_wars;
delete from public.season_clan_ratings;
delete from public.clan_members;
delete from public.clans;

delete from public.marriage_requests;
delete from public.marriages;
delete from public.relationship_requests;
delete from public.relationships;

delete from public.telegram_chat_activity;
delete from public.telegram_chat_activity_legacy;
delete from public.telegram_chat_daily_snapshot;
delete from public.telegram_chat_profile_snapshot;
delete from public.telegram_chat_history_imports;
delete from public.telegram_chat_import_state;
delete from public.telegram_chat_import_user_baseline;

delete from public.iris_chat_stats_archive;
delete from public.iris_clan_import_archive;
delete from public.iris_inactive_snapshot;
delete from public.iris_marriage_import_archive;
delete from public.iris_nickname_import_archive;

create or replace function public.bot_list_current_participants()
returns json
language sql
security definer
set search_path='public'
as $function$
  select coalesce(
    json_agg(
      json_build_object(
        'display_name', coalesce(u.full_name, u.first_name, u.minecraft_nickname, 'Участник PRISMA'),
        'username', u.telegram_username,
        'telegram_id', u.telegram_id,
        'nickname', u.minecraft_nickname
      )
      order by lower(coalesce(u.minecraft_nickname,'')), u.telegram_id
    ),
    '[]'::json
  )
  from public.users u
  where u.status='ACCEPTED'
    and u.is_whitelisted
    and not u.is_banned
    and u.deleted_at is null;
$function$;

revoke execute on function public.bot_list_current_participants() from public,anon,authenticated;
grant execute on function public.bot_list_current_participants() to service_role;

drop function if exists public.bot_list_iris_nicknames();
drop function if exists public.bot_list_iris_inactive_snapshot();
