create or replace function public.bot_create_clan_war(p_tg_id bigint,p_target text)
returns jsonb language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_create_clan_war(uid,p_target);
end;
$function$;

create or replace function public.bot_respond_clan_war(p_tg_id bigint,p_war_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_respond_clan_war(uid,p_war_id,p_action);
end;
$function$;

create or replace function public.bot_start_clan_war(p_tg_id bigint,p_war_id uuid)
returns jsonb language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_start_clan_war(uid,p_war_id);
end;
$function$;

create or replace function public.bot_finish_clan_war(p_tg_id bigint,p_war_id uuid,p_score_a integer,p_score_b integer)
returns jsonb language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_finish_clan_war(uid,p_war_id,p_score_a,p_score_b);
end;
$function$;

revoke execute on function public.bot_create_clan_war(bigint,text) from public,anon,authenticated;
grant execute on function public.bot_create_clan_war(bigint,text) to service_role;
revoke execute on function public.bot_respond_clan_war(bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.bot_respond_clan_war(bigint,uuid,text) to service_role;
revoke execute on function public.bot_start_clan_war(bigint,uuid) from public,anon,authenticated;
grant execute on function public.bot_start_clan_war(bigint,uuid) to service_role;
revoke execute on function public.bot_finish_clan_war(bigint,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.bot_finish_clan_war(bigint,uuid,integer,integer) to service_role;