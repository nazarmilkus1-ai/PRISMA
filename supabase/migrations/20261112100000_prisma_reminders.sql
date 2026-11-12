-- Reminders for members and staff, delivered by the existing notification worker:
-- a reminder is a notifications row (kind REMINDER) with a future available_at.
create or replace function public.bot_create_reminder(p_tg_id bigint, p_text text, p_at timestamptz)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare nid uuid; pending int; clean text := btrim(coalesce(p_text,''));
begin
  if p_tg_id is null then raise exception 'USER_REQUIRED'; end if;
  if char_length(clean) < 1 or char_length(clean) > 300 then raise exception 'REMINDER_TEXT_INVALID'; end if;
  if p_at is null or p_at < now() + interval '20 seconds' then raise exception 'REMINDER_TIME_PAST'; end if;
  if p_at > now() + interval '366 days' then raise exception 'REMINDER_TIME_TOO_FAR'; end if;
  select count(*) into pending from public.notifications
   where kind = 'REMINDER' and status = 'pending' and (data->>'owner')::bigint = p_tg_id;
  if pending >= 20 then raise exception 'REMINDER_LIMIT'; end if;
  insert into public.notifications(telegram_id, channel, kind, title, body, data, available_at)
  values (p_tg_id, 'telegram', 'REMINDER', '⏰ Напоминание', clean, jsonb_build_object('owner', p_tg_id), p_at)
  returning id into nid;
  return jsonb_build_object('id', nid, 'at', p_at);
end; $function$;

create or replace function public.bot_list_reminders(p_tg_id bigint)
returns jsonb language sql security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', body, 'at', available_at) order by available_at), '[]'::jsonb)
  from (select id, body, available_at from public.notifications
         where kind = 'REMINDER' and status = 'pending' and (data->>'owner')::bigint = p_tg_id
         order by available_at limit 20) r;
$function$;

create or replace function public.bot_cancel_reminder(p_tg_id bigint, p_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare n int;
begin
  update public.notifications set status = 'cancelled', updated_at = now()
   where id = p_id and kind = 'REMINDER' and status = 'pending' and (data->>'owner')::bigint = p_tg_id;
  get diagnostics n = row_count;
  return n > 0;
end; $function$;

revoke all on function public.bot_create_reminder(bigint,text,timestamptz) from public, anon, authenticated;
revoke all on function public.bot_list_reminders(bigint) from public, anon, authenticated;
revoke all on function public.bot_cancel_reminder(bigint,uuid) from public, anon, authenticated;
grant execute on function public.bot_create_reminder(bigint,text,timestamptz) to service_role;
grant execute on function public.bot_list_reminders(bigint) to service_role;
grant execute on function public.bot_cancel_reminder(bigint,uuid) to service_role;
