alter table public.clan_invitations
  drop constraint if exists clan_invitations_clan_id_invitee_id_status_key;

create unique index if not exists clan_invitations_pending_unique_idx
  on public.clan_invitations (clan_id, invitee_id)
  where status = 'pending';