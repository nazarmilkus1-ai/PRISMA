create index if not exists chat_logs_created_at_idx
  on public.chat_logs (created_at);

create or replace function public.chat_logs_activity_after_insert()
returns trigger
language plpgsql
as $$
begin
  if new.user_id is not null then
    update public.users
       set activity_score = greatest(0, coalesce(activity_score, 0) + 1),
           last_seen_at = greatest(coalesce(last_seen_at, new.created_at), new.created_at)
     where id = new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists chat_logs_activity_after_insert on public.chat_logs;

create trigger chat_logs_activity_after_insert
after insert on public.chat_logs
for each row
execute function public.chat_logs_activity_after_insert();

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'prisma-chat-logs-retention'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end $$;

select cron.schedule(
  'prisma-chat-logs-retention',
  '0 * * * *',
  $job$
    delete from public.chat_logs
    where created_at < now() - interval '2 days';
  $job$
);
