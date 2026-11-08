-- PRISMA participant site: bind Supabase Auth identities to users and add participant-safe RLS.
alter table public.users
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

create index if not exists users_auth_user_id_idx on public.users(auth_user_id);

with latest_login as (
  select distinct on (telegram_id)
    telegram_id,
    auth_user_id
  from public.login_history
  where success = true
    and auth_user_id is not null
  order by telegram_id, created_at desc
)
update public.users u
set auth_user_id = l.auth_user_id,
    updated_at = now()
from latest_login l
where u.auth_user_id is null
  and u.telegram_id = l.telegram_id;

grant select on table public.poll_options, public.notification_preferences to authenticated;
grant update on table public.notification_preferences to authenticated;

drop policy if exists users_participant_read on public.users;
create policy users_participant_read
  on public.users for select to authenticated
  using ((select auth.uid()) = auth_user_id);

drop policy if exists applications_participant_read on public.applications;
create policy applications_participant_read
  on public.applications for select to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = applications.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists reports_participant_read on public.reports;
create policy reports_participant_read
  on public.reports for select to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = reports.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists report_history_participant_read on public.report_history;
create policy report_history_participant_read
  on public.report_history for select to authenticated
  using (
    exists (
      select 1 from public.reports r
      join public.users u on u.id = r.user_id
      where r.id = report_history.report_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists notifications_participant_read on public.notifications;
create policy notifications_participant_read
  on public.notifications for select to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = notifications.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists notification_preferences_participant_read on public.notification_preferences;
create policy notification_preferences_participant_read
  on public.notification_preferences for select to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = notification_preferences.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists notification_preferences_participant_update on public.notification_preferences;
create policy notification_preferences_participant_update
  on public.notification_preferences for update to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = notification_preferences.user_id
        and u.auth_user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.users u
      where u.id = notification_preferences.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists clan_members_participant_read on public.clan_members;
create policy clan_members_participant_read
  on public.clan_members for select to authenticated
  using (
    exists (
      select 1
      from public.users me
      where me.auth_user_id = (select auth.uid())
        and me.clan_id = clan_members.clan_id
    )
  );

drop policy if exists clan_invitations_participant_read on public.clan_invitations;
create policy clan_invitations_participant_read
  on public.clan_invitations for select to authenticated
  using (
    invitee_id in (
      select u.id from public.users u
      where u.auth_user_id = (select auth.uid())
    )
    or clan_id in (
      select u.clan_id from public.users u
      where u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists clan_activity_participant_read on public.clan_activity;
create policy clan_activity_participant_read
  on public.clan_activity for select to authenticated
  using (
    clan_id in (
      select u.clan_id from public.users u
      where u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists clan_announcements_participant_read on public.clan_announcements;
create policy clan_announcements_participant_read
  on public.clan_announcements for select to authenticated
  using (
    clan_id in (
      select u.clan_id from public.users u
      where u.auth_user_id = (select auth.uid())
    )
  );

drop policy if exists clan_wars_participant_read on public.clan_wars;
create policy clan_wars_participant_read
  on public.clan_wars for select to authenticated
  using (
    clan_a in (select u.clan_id from public.users u where u.auth_user_id = (select auth.uid()))
    or clan_b in (select u.clan_id from public.users u where u.auth_user_id = (select auth.uid()))
  );

drop policy if exists poll_options_participant_read on public.poll_options;
create policy poll_options_participant_read
  on public.poll_options for select to authenticated
  using (
    exists (
      select 1 from public.polls p
      where p.id = poll_options.poll_id
        and p.visibility = 'public'
    )
  );

drop policy if exists poll_votes_participant_read on public.poll_votes;
create policy poll_votes_participant_read
  on public.poll_votes for select to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id = poll_votes.user_id
        and u.auth_user_id = (select auth.uid())
    )
  );
