CREATE OR REPLACE FUNCTION public.bot_start_battle(
  p_tg_id bigint,
  p_opponent_nickname text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;

  return private.prisma_participant_start_battle(uid,p_opponent_nickname);
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_get_battles(
  p_tg_id bigint,
  p_limit integer DEFAULT 10
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare uid uuid;
begin
  select id into uid
  from public.users
  where telegram_id=p_tg_id and deleted_at is null
  limit 1;

  if uid is null then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  return coalesce((
    select json_agg(x order by x.created_at desc)
    from (
      select
        pb.id,
        c.minecraft_nickname as challenger_nickname,
        o.minecraft_nickname as opponent_nickname,
        pb.challenger_score,
        pb.opponent_score,
        pb.winner_id,
        pb.points_awarded,
        pb.status,
        pb.created_at
      from public.player_battles pb
      join public.users c on c.id=pb.challenger_id
      join public.users o on o.id=pb.opponent_id
      where pb.challenger_id=uid or pb.opponent_id=uid
      order by pb.created_at desc
      limit greatest(1,least(coalesce(p_limit,10),30))
    ) x
  ),'[]'::json);
end;
$function$;

REVOKE ALL ON FUNCTION public.bot_start_battle(bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bot_get_battles(bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bot_start_battle(bigint,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_get_battles(bigint,integer) TO service_role;
