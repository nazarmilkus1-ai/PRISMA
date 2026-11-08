alter table public.notifications drop constraint if exists notifications_status_check;
alter table public.notifications add constraint notifications_status_check
  check (status = any (array[
    'pending'::text,
    'sending'::text,
    'sent'::text,
    'read'::text,
    'failed'::text,
    'cancelled'::text
  ]));