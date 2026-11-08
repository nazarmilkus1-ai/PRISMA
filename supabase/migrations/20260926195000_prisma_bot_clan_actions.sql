create or replace function public.bot_cancel_clan_invite(
  p_tg_id bigint,
  p_invite_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_cancel_clan_invite(uid,p_invite_id);
end;
$function$;

revoke all on function public.bot_cancel_clan_invite(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_cancel_clan_invite(bigint,uuid) to service_role;