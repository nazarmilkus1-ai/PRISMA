create or replace function public.chat_logs_activity_after_insert()
returns trigger
language plpgsql
set search_path = public, pg_temp
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
