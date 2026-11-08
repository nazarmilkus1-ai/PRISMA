-- Restore explicit Data API grants for the authenticated admin dashboard.
-- RLS remains enabled and existing permission policies remain the row-level gate.

grant select on table
  public.users,
  public.applications,
  public.application_history,
  public.reports,
  public.report_history,
  public.moderation_logs,
  public.chat_logs,
  public.chat_settings,
  public.clans,
  public.clan_members,
  public.clan_invitations,
  public.clan_alliances,
  public.clan_wars,
  public.clan_activity,
  public.clan_announcements,
  public.polls,
  public.poll_ratings,
  public.poll_votes,
  public.news,
  public.audit_logs,
  public.notifications,
  public.server_nodes,
  public.server_metrics,
  public.minecraft_events,
  public.backup_runs,
  public.roles,
  public.permissions,
  public.role_permissions,
  public.admins
to authenticated;

drop policy if exists notifications_staff_read on public.notifications;
create policy notifications_staff_read
  on public.notifications for select to authenticated
  using ((select private.has_permission('admin.view_audit')));

drop policy if exists server_metrics_staff_read on public.server_metrics;
create policy server_metrics_staff_read
  on public.server_metrics for select to authenticated
  using ((select private.has_permission('system.health')));

drop policy if exists minecraft_events_staff_read on public.minecraft_events;
create policy minecraft_events_staff_read
  on public.minecraft_events for select to authenticated
  using ((select private.has_permission('system.health') or private.has_permission('player.view')));

drop policy if exists poll_ratings_staff_read on public.poll_ratings;
create policy poll_ratings_staff_read
  on public.poll_ratings for select to authenticated
  using ((select private.has_permission('poll.view') or private.has_permission('analytics.view')));

drop policy if exists poll_votes_staff_read on public.poll_votes;
create policy poll_votes_staff_read
  on public.poll_votes for select to authenticated
  using ((select private.has_permission('poll.view') or private.has_permission('analytics.view')));

drop policy if exists clan_members_staff_read on public.clan_members;
create policy clan_members_staff_read
  on public.clan_members for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists clan_invitations_staff_read on public.clan_invitations;
create policy clan_invitations_staff_read
  on public.clan_invitations for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists clan_alliances_staff_read on public.clan_alliances;
create policy clan_alliances_staff_read
  on public.clan_alliances for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists clan_wars_staff_read on public.clan_wars;
create policy clan_wars_staff_read
  on public.clan_wars for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists clan_activity_staff_read on public.clan_activity;
create policy clan_activity_staff_read
  on public.clan_activity for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists clan_announcements_staff_read on public.clan_announcements;
create policy clan_announcements_staff_read
  on public.clan_announcements for select to authenticated
  using ((select private.has_permission('clan.view_all') or private.has_permission('clan.manage')));

drop policy if exists application_history_staff_read on public.application_history;
create policy application_history_staff_read
  on public.application_history for select to authenticated
  using ((select private.has_permission('application.view') or private.has_permission('application.review')));

drop policy if exists report_history_staff_read on public.report_history;
create policy report_history_staff_read
  on public.report_history for select to authenticated
  using ((select private.has_permission('report.view') or private.has_permission('report.resolve')));

drop policy if exists backup_runs_staff_read on public.backup_runs;
create policy backup_runs_staff_read
  on public.backup_runs for select to authenticated
  using ((select private.has_permission('settings.view') or private.has_permission('admin.manage')));

insert into public.admins (user_id, role_id)
select u.id, r.id
from public.users u
cross join public.roles r
where r.name = 'owner'
  and u.telegram_id in (8285627083, 8131532899, 8719730740, 5898676599, 5880980415, 5242653070)
on conflict (user_id) do update set role_id = excluded.role_id;
