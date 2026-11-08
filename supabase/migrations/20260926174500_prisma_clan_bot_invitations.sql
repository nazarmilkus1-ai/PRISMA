create or replace function public.bot_list_clan_invites(p_tg_id bigint)
returns json
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_list_clan_invites(uid);
end;
$function$;

create or replace function public.bot_accept_clan_invite(p_tg_id bigint,p_invite_id uuid)
returns json
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_accept_clan_invite(uid,p_invite_id);
end;
$function$;

create or replace function public.bot_decline_clan_invite(p_tg_id bigint,p_invite_id uuid)
returns json
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_decline_clan_invite(uid,p_invite_id);
end;
$function$;

revoke execute on function public.bot_list_clan_invites(bigint) from public,anon,authenticated;
grant execute on function public.bot_list_clan_invites(bigint) to service_role;
revoke execute on function public.bot_accept_clan_invite(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_accept_clan_invite(bigint,uuid) to service_role;
revoke execute on function public.bot_decline_clan_invite(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_decline_clan_invite(bigint,uuid) to service_role;