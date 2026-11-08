-- PRISMA v2: trusted Telegram notification worker RPCs.
-- Atomic claim uses FOR UPDATE SKIP LOCKED and returns only claimed rows.

create or replace function public.bot_claim_notifications(p_limit integer default 20)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  lim integer:=greatest(1,least(coalesce(p_limit,20),100));
  now_ts timestamptz:=now();
  stale_cutoff timestamptz:=now()-interval '15 minutes';
  claimed json;
begin
  update public.notifications
  set status='failed',last_error='STALE_SENDING_MAX_ATTEMPTS',updated_at=now_ts
  where status='sending' and attempts>=5 and updated_at<stale_cutoff;

  update public.notifications
  set status='pending',available_at=now_ts,last_error='RECOVERED_STALE_SENDING',updated_at=now_ts
  where status='sending' and attempts<5 and updated_at<stale_cutoff;

  with picked as (
    select n.id
    from public.notifications n
    where n.status='pending' and n.attempts<5 and n.available_at<=now_ts
    order by n.created_at,n.id
    for update skip locked
    limit lim
  ),
  claimed_rows as (
    update public.notifications n
    set status='sending',attempts=n.attempts+1,updated_at=now_ts
    from picked
    where n.id=picked.id
    returning n.id,n.user_id,n.telegram_id,n.kind,n.title,n.body,n.data,n.attempts,n.created_at
  )
  select coalesce(json_agg(
    json_build_object(
      'id',c.id,'user_id',c.user_id,'telegram_id',coalesce(c.telegram_id,u.telegram_id),
      'kind',c.kind,'title',c.title,'body',c.body,'data',c.data,'attempts',c.attempts
    ) order by c.created_at,c.id
  ),'[]'::json)
  into claimed
  from claimed_rows c
  left join public.users u on u.id=c.user_id;

  return claimed;
end;
$function$;

revoke all on function public.bot_claim_notifications(integer) from public,anon,authenticated;
grant execute on function public.bot_claim_notifications(integer) to service_role;

create or replace function public.bot_get_notification_preference(p_user_id uuid,p_key text)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare enabled boolean;
begin
  if p_user_id is null then return true; end if;
  if p_key is null or p_key not in ('news','events','server_status','clan_news','social','battles','market','moderation','polls') then return true; end if;
  insert into public.notification_preferences(user_id) values(p_user_id) on conflict(user_id) do nothing;
  execute format('select %I from public.notification_preferences where user_id=$1',p_key) into enabled using p_user_id;
  return coalesce(enabled,true);
end;
$function$;

revoke all on function public.bot_get_notification_preference(uuid,text) from public,anon,authenticated;
grant execute on function public.bot_get_notification_preference(uuid,text) to service_role;

create or replace function public.bot_finish_notification(
 p_notification_id uuid,
 p_status text,
 p_error text default null,
 p_retry_after_seconds integer default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare status_value text:=lower(trim(p_status)); updated_count integer; now_ts timestamptz:=now();
begin
  if status_value not in ('sent','pending','failed','cancelled') then raise exception 'INVALID_NOTIFICATION_STATUS'; end if;
  if p_retry_after_seconds is not null and (p_retry_after_seconds<0 or p_retry_after_seconds>3600) then raise exception 'INVALID_RETRY_DELAY'; end if;

  update public.notifications
  set status=status_value,
      updated_at=now_ts,
      sent_at=case when status_value='sent' then now_ts else sent_at end,
      available_at=case when status_value='pending' and p_retry_after_seconds is not null then now_ts+make_interval(secs=>p_retry_after_seconds) else available_at end,
      last_error=case when p_error is null then last_error else left(p_error,1000) end
  where id=p_notification_id;

  get diagnostics updated_count=row_count;
  if updated_count=0 then raise exception 'NOTIFICATION_NOT_FOUND'; end if;
  return json_build_object('success',true,'id',p_notification_id,'status',status_value);
end;
$function$;

revoke all on function public.bot_finish_notification(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.bot_finish_notification(uuid,text,text,integer) to service_role;
