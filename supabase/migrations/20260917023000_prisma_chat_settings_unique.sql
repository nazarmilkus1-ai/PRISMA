-- Allow reliable per-chat UPSERTs used by the automoderation panel.
-- Existing duplicate chat_id values were checked before this migration.
create unique index if not exists chat_settings_chat_id_uidx
  on public.chat_settings(chat_id)
  where chat_id is not null;
