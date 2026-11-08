-- The participant dashboard reads the authenticated user's stats directly.
grant select on table public.player_stats to authenticated;
