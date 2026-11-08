-- Participant site: allow an authenticated player to read only their own clan row.
drop policy if exists clans_participant_read on public.clans;

create policy clans_participant_read
  on public.clans for select to authenticated
  using (
    exists (
      select 1
      from public.users u
      where u.auth_user_id = (select auth.uid())
        and u.clan_id = clans.id
    )
  );
