-- PRISMA performance/index cleanup.
-- No data is removed; only redundant indexes are dropped and missing FK indexes added.

-- Redundant indexes reported by Supabase advisor.
drop index if exists public.automod_events_chat_idx;
drop index if exists public.poll_ratings_unique_choice_uidx;

-- Cover core foreign keys used by the control plane.
create index if not exists admins_role_id_idx on public.admins(role_id);
create index if not exists news_created_by_idx on public.news(created_by);
create index if not exists poll_options_poll_id_idx on public.poll_options(poll_id);
create index if not exists poll_votes_option_id_idx on public.poll_votes(option_id);
create index if not exists poll_votes_user_id_idx on public.poll_votes(user_id);
create index if not exists reports_user_id_idx on public.reports(user_id);
create index if not exists role_permissions_permission_id_idx on public.role_permissions(permission_id);
create index if not exists users_clan_id_idx on public.users(clan_id);
