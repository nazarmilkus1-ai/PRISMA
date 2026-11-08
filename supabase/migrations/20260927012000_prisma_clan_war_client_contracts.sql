create or replace function public.bot_list_clan_wars(p_tg_id bigint)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid; cid uuid;
begin
  select id,clan_id into uid,cid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then return jsonb_build_object('error','USER_NOT_FOUND'); end if;
  if cid is null then return jsonb_build_object('error','NO_CLAN'); end if;

  return jsonb_build_object(
    'wars',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',w.id,
        'opponent',case when w.clan_a=cid then cb.name else ca.name end,
        'opponent_tag',case when w.clan_a=cid then cb.tag else ca.tag end,
        'status',w.status,
        'scheduled_at',w.scheduled_at,
        'score_for',case when w.clan_a=cid then w.score_a else w.score_b end,
        'score_against',case when w.clan_a=cid then w.score_b else w.score_a end,
        'winner_clan_id',w.winner_clan_id,
        'incoming',w.status='pending' and w.clan_b=cid
      ) order by case w.status when 'pending' then 0 when 'scheduled' then 1 when 'active' then 2 else 3 end,w.id)
      from public.clan_wars w
      join public.clans ca on ca.id=w.clan_a
      join public.clans cb on cb.id=w.clan_b
      where w.clan_a=cid or w.clan_b=cid
    ),'[]'::jsonb)
  );
end;
$function$;

create or replace function public.mc_list_clan_wars(p_user_id uuid)
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.status_order,x.id),'[]'::json)
from (
  select
    w.id,
    case when w.clan_a=cm.clan_id then cb.name else ca.name end opponent,
    case when w.clan_a=cm.clan_id then cb.tag else ca.tag end opponent_tag,
    w.status,w.scheduled_at,
    case when w.clan_a=cm.clan_id then w.score_a else w.score_b end score_for,
    case when w.clan_a=cm.clan_id then w.score_b else w.score_a end score_against,
    w.winner_clan_id,
    (w.status='pending' and w.clan_b=cm.clan_id) incoming,
    row_number() over (
      order by case w.status when 'pending' then 0 when 'scheduled' then 1 when 'active' then 2 else 3 end,w.id
    )::integer status_order
  from public.clan_members cm
  join public.clan_wars w on w.clan_a=cm.clan_id or w.clan_b=cm.clan_id
  join public.clans ca on ca.id=w.clan_a
  join public.clans cb on cb.id=w.clan_b
  where cm.user_id=p_user_id and cm.status='active'
  order by case w.status when 'pending' then 0 when 'scheduled' then 1 when 'active' then 2 else 3 end,w.id
  limit 50
) x;
$function$;

create or replace function public.mc_create_clan_war(p_user_id uuid,p_target text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  return private.prisma_participant_create_clan_war(p_user_id,p_target);
end;
$function$;

create or replace function public.mc_respond_clan_war(p_user_id uuid,p_war_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  return private.prisma_participant_respond_clan_war(p_user_id,p_war_id,p_action);
end;
$function$;

create or replace function public.mc_start_clan_war(p_user_id uuid,p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  return private.prisma_participant_start_clan_war(p_user_id,p_war_id);
end;
$function$;

create or replace function public.mc_finish_clan_war(p_user_id uuid,p_war_id uuid,p_score_a integer,p_score_b integer)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  return private.prisma_participant_finish_clan_war(p_user_id,p_war_id,p_score_a,p_score_b);
end;
$function$;

revoke execute on function public.bot_list_clan_wars(bigint) from public,anon,authenticated;
grant execute on function public.bot_list_clan_wars(bigint) to service_role;

revoke execute on function public.mc_list_clan_wars(uuid) from public,anon,authenticated;
grant execute on function public.mc_list_clan_wars(uuid) to service_role;
revoke execute on function public.mc_create_clan_war(uuid,text) from public,anon,authenticated;
grant execute on function public.mc_create_clan_war(uuid,text) to service_role;
revoke execute on function public.mc_respond_clan_war(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mc_respond_clan_war(uuid,uuid,text) to service_role;
revoke execute on function public.mc_start_clan_war(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mc_start_clan_war(uuid,uuid) to service_role;
revoke execute on function public.mc_finish_clan_war(uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.mc_finish_clan_war(uuid,uuid,integer,integer) to service_role;