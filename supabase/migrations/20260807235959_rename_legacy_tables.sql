-- Non-destructive: the project already had a simpler hand-built
-- users/applications setup (telegram_id as PK, a generic `answers` jsonb
-- blob, lowercase status strings) with one real row in each — including
-- xN4ZARx's own already-approved application. That schema can't support
-- clans, moderation logs, chat logs, polls or reports, so we're moving
-- forward to the fuller schema, but nothing is deleted: the old tables are
-- kept in full under a _legacy_v0 suffix. Drop them yourself once you've
-- confirmed nothing else still points at the old names.
alter table if exists public.users rename to users_legacy_v0;
alter table if exists public.applications rename to applications_legacy_v0;