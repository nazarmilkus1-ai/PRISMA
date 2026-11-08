-- PRISMA v2: canonical authenticated battle history gateway.
-- Only battles where the caller is challenger or opponent are returned.
create or replace function public.participant_get_battles(p_limit integer default 20)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(jsonb_agg(
  jsonb_build_object(
    'id', x.id,
    'challenger_id', x.challenger_id,
    'opponent_id', x.opponent_id,
    'challenger_score', x.challenger_score,
    'opponent_score', x.opponent_score,
    'winner_id', x.winner_id,
    'points_awarded', x.points_awarded,
    'status', x.status,
    'created_at', x.created_at,
    'challenger', jsonb_build_object('minecraft_nickname', x.challenger_nickname),
    'opponent', jsonb_build_object('minecraft_nickname', x.opponent_nickname),
    'winner', case
      when x.winner_id is null then null
      else jsonb_build_object('minecraft_nickname', x.winner_nickname)
    end
  )
  order by x.created_at desc
), '[]'::jsonb)
from (
  select
    b.id,
    b.challenger_id,
    b.opponent_id,
    b.challenger_score,
    b.opponent_score,
    b.winner_id,
    b.points_awarded,
    b.status,
    b.created_at,
    challenger.minecraft_nickname as challenger_nickname,
    opponent.minecraft_nickname as opponent_nickname,
    winner.minecraft_nickname as winner_nickname
  from public.player_battles b
  join public.users me
    on me.auth_user_id = (select auth.uid())
   and me.deleted_at is null
  join public.users challenger
    on challenger.id = b.challenger_id
  join public.users opponent
    on opponent.id = b.opponent_id
  left join public.users winner
    on winner.id = b.winner_id
  where (b.challenger_id = me.id or b.opponent_id = me.id)
  order by b.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100)
) x;
$function$;

revoke execute on function public.participant_get_battles(integer) from public, anon;
grant execute on function public.participant_get_battles(integer) to authenticated;
grant execute on function public.participant_get_battles(integer) to postgres;
