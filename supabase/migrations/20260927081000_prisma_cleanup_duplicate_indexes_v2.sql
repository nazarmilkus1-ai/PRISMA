-- Re-establish the canonical index state after notification preference hardening.
alter table public.notification_preferences
  drop constraint if exists notification_preferences_user_id_key;

drop index if exists public.idx_clan_activity_clan_created;
