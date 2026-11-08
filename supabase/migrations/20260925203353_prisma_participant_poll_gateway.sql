-- Authenticated voting gateway. Browser submits only poll/option IDs;
-- the Telegram identity is resolved from auth.uid().

create or replace function public.participant_vote_poll(
  p_poll_id uuid,p_option_id uuid
) returns json
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid; tg_id bigint;
begin
  select u.id,u.telegram_id into uid,tg_id
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  if tg_id is null then raise exception 'TELEGRAM_NOT_LINKED'; end if;

  return public.bot_vote_poll(p_poll_id,p_option_id,tg_id);
end;
$function$;

revoke all on function public.participant_vote_poll(uuid,uuid) from public,anon;
grant execute on function public.participant_vote_poll(uuid,uuid) to authenticated;
