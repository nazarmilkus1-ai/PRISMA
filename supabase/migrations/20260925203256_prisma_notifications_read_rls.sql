-- Participant notification read-state through RLS.

drop policy if exists notifications_participant_update on public.notifications;
create policy notifications_participant_update
  on public.notifications for update to authenticated
  using (
    exists (
      select 1 from public.users u
      where u.id=notifications.user_id
        and u.auth_user_id=(select auth.uid())
        and u.deleted_at is null
    )
  )
  with check (
    exists (
      select 1 from public.users u
      where u.id=notifications.user_id
        and u.auth_user_id=(select auth.uid())
        and u.deleted_at is null
    )
  );

revoke update on public.notifications from authenticated;
grant update(status,updated_at) on public.notifications to authenticated;
