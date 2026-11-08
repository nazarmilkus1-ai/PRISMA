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
        case
          when pb.winner_id is null then 'DRAW'
          when pb.winner_id=uid then 'WIN'
          else 'LOSS'
        end as viewer_result,
        case
          when pb.winner_id is null then 0
          when pb.winner_id=uid then pb.points_awarded
          else -pb.points_awarded
        end as viewer_delta,
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

REVOKE ALL ON FUNCTION public.bot_get_battles(bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bot_get_battles(bigint,integer) TO service_role;
