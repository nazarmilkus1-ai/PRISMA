alter table public.applications
  add column if not exists is_archived boolean not null default false;

create index if not exists applications_archived_created_idx
  on public.applications (is_archived, created_at desc);


alter table public.application_history drop constraint if exists application_history_action_check;
alter table public.application_history add constraint application_history_action_check check (action = any (array['CREATED','APPROVED','REJECTED','REOPENED','ARCHIVED']));
