-- Canonical bot clan gateway: the bot uses the same clan permission model as site/plugin.

create or replace function public.bot_clan_invite(
  p_tg_id bigint,
  p_target_nickname text
)
returns json
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
  return public.mc_invite_player(uid,p_target_nickname)::json;
end;
$function$;

create or replace function public.bot_clan_invite(
  p_actor_tg bigint,
  p_target_tg bigint
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_nickname text;
begin
  select minecraft_nickname into v_nickname
  from public.users
  where telegram_id=p_target_tg
    and deleted_at is null
  limit 1;

  if v_nickname is null or trim(v_nickname)='' then
    raise exception 'PLAYER_NOT_FOUND';
  end if;

  return public.bot_clan_invite(p_actor_tg,v_nickname);
end;
$function$;

create or replace function public.bot_set_clan_role(
  p_tg_id bigint,
  p_target_nickname text,
  p_role text
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
  return public.mc_set_clan_role(uid,p_target_nickname,p_role);
end;
$function$;

create or replace function public.bot_get_clan_activity(p_tg_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  cid uuid;
begin
  select u.id,u.clan_id into uid,cid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if cid is null then raise exception 'NO_CLAN'; end if;

  return private.prisma_participant_get_clan_activity(uid,cid);
end;
$function$;

create or replace function public.bot_get_clan_achievements(p_tg_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  cid uuid;
begin
  select u.id,u.clan_id into uid,cid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if cid is null then raise exception 'NO_CLAN'; end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'achievement_id',ca.achievement_id,
          'unlocked_at',ca.unlocked_at,
          'title',a.title,
          'description',a.description,
          'icon',a.icon,
          'xp_reward',a.xp_reward
        )
        order by ca.unlocked_at desc
      )
      from public.clan_achievements ca
      join public.achievements a on a.id=ca.achievement_id
      where ca.clan_id=cid
    ),
    '[]'::jsonb
  );
end;
$function$;

revoke all on function public.bot_clan_invite(bigint,text) from public,anon,authenticated;
revoke all on function public.bot_clan_invite(bigint,bigint) from public,anon,authenticated;
revoke all on function public.bot_set_clan_role(bigint,text,text) from public,anon,authenticated;
revoke all on function public.bot_get_clan_activity(bigint) from public,anon,authenticated;
revoke all on function public.bot_get_clan_achievements(bigint) from public,anon,authenticated;

grant execute on function public.bot_clan_invite(bigint,text) to service_role;
grant execute on function public.bot_clan_invite(bigint,bigint) to service_role;
grant execute on function public.bot_set_clan_role(bigint,text,text) to service_role;
grant execute on function public.bot_get_clan_activity(bigint) to service_role;
grant execute on function public.bot_get_clan_achievements(bigint) to service_role;
