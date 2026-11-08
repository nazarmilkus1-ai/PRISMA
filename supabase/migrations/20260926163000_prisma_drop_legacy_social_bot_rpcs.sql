-- The bot now uses the hardened bot_social_* contract.
-- Remove the superseded Telegram-specific social RPCs so two APIs cannot drift.
drop function if exists public.bot_relationship_request(bigint,bigint);
drop function if exists public.bot_relationship_respond(bigint,boolean);
drop function if exists public.bot_relationship_end(bigint,bigint);
drop function if exists public.bot_relationship_info(bigint);
drop function if exists public.bot_marriage_request(bigint,bigint);
drop function if exists public.bot_marriage_respond(bigint,boolean);
drop function if exists public.bot_marriage_divorce(bigint);
drop function if exists public.bot_marriage_info(bigint);
