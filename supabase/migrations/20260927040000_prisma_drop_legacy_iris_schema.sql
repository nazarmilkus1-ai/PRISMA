drop table if exists public.iris_nickname_import_archive cascade;
drop table if exists public.iris_marriage_import_archive cascade;
drop table if exists public.iris_inactive_snapshot cascade;
drop table if exists public.iris_clan_import_archive cascade;
drop table if exists public.iris_chat_stats_archive cascade;

drop table if exists public.telegram_chat_import_user_baseline cascade;
drop table if exists public.telegram_chat_import_state cascade;
drop table if exists public.telegram_chat_history_imports cascade;
drop table if exists public.telegram_chat_profile_snapshot cascade;
drop table if exists public.telegram_chat_daily_snapshot cascade;
drop table if exists public.telegram_chat_activity_legacy cascade;

drop function if exists public.bot_list_iris_nicknames();
drop function if exists public.bot_list_iris_inactive_snapshot();
drop function if exists public.bot_list_iris_clan_archive();
drop function if exists public.bot_get_iris_clan_by_number(integer);
