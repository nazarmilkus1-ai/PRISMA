create or replace function public.mc_list_clans(p_limit integer default 20)
returns json
language sql stable security definer set search_path=''
as $function$
select json_build_object(
  'clans',
  coalesce(json_agg(x order by x.rating desc,x.level desc,x.name),'[]'::json)
)
from (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.wins,c.losses,c.description,c.type,
         row_number() over(order by c.rating desc,c.level desc,c.name,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
  order by c.rating desc,c.level desc,c.name,c.id
  limit greatest(1,least(coalesce(p_limit,20),100))
) x;
$function$;