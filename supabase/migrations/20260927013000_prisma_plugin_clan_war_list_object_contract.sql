create or replace function public.mc_list_clan_wars(p_user_id uuid)
returns json
language sql stable security definer set search_path=''
as $function$
select json_build_object(
  'wars',
  coalesce(json_agg(x order by x.status_order,x.id),'[]'::json)
)
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
    case w.status when 'pending' then 0 when 'scheduled' then 1 when 'active' then 2 else 3 end status_order
  from public.clan_members cm
  join public.clan_wars w on w.clan_a=cm.clan_id or w.clan_b=cm.clan_id
  join public.clans ca on ca.id=w.clan_a
  join public.clans cb on cb.id=w.clan_b
  where cm.user_id=p_user_id and cm.status='active'
  order by case w.status when 'pending' then 0 when 'scheduled' then 1 when 'active' then 2 else 3 end,w.id
  limit 50
) x;
$function$;