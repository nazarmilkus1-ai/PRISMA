-- Backend-only access fixes for the admin dashboard, notification worker and Minecraft plugin.
--
-- chat_settings previously used a partial unique index on chat_id. PostgreSQL
-- cannot use a partial unique index as the target of ON CONFLICT (chat_id).
drop index if exists public.chat_settings_chat_id_uidx;
create unique index if not exists chat_settings_chat_id_uidx
  on public.chat_settings (chat_id);

grant all privileges on table public.notifications to service_role;
grant all privileges on table public.minecraft_events to service_role;
grant all privileges on table public.server_metrics to service_role;
grant all privileges on table public.login_history to service_role;
grant all privileges on table public.backup_runs to service_role;
