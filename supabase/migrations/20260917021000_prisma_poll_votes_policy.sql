-- Keep normalized poll votes explicitly covered by RLS.
-- service_role still bypasses RLS, while other roles have no table grants.

drop policy if exists "service role poll votes" on public.poll_votes;
create policy "service role poll votes"
  on public.poll_votes
  for all
  to service_role
  using (true)
  with check (true);
