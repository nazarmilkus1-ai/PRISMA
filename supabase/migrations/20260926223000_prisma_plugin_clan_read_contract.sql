create or replace function public.mc_list_clans(p_limit integer default 20)
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.rating desc,x.level desc,x.name),'[]'::json)
from (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.wins,c.losses,c.description,c.type,
         row_number() over(order by c.rating desc,c.level desc,c.name,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
  order by c.rating desc,c.level desc,c.name,c.id
  limit greatest(1,least(coalesce(p_limit,20),100))
) x;
$function$;

create or replace function public.mc_get_clan_by_identifier(p_identifier text)
returns json
language sql stable security definer set search_path=''
as $function$
select case
  when c.id is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'id',c.id,'name',c.name,'tag',c.tag,'description',c.description,
    'rating',c.rating,'level',c.level,'xp',c.xp,'wins',c.wins,'losses',c.losses,
    'type',c.type,'status',c.status,'created_at',c.created_at,
    'owner_id',c.owner_id,
    'owner',json_build_object(
      'minecraft_nick',owner.minecraft_nickname,
      'username',owner.telegram_username,
      'full_name',owner.full_name
    )
  )
end
from public.clans c
left join public.users owner on owner.id=c.owner_id
where c.deleted_at is null and c.status='active'
  and (
    c.id::text=trim(coalesce(p_identifier,''))
    or lower(c.tag)=lower(trim(coalesce(p_identifier,'')))
    or lower(c.name)=lower(trim(coalesce(p_identifier,'')))
  )
limit 1;
$function$;

revoke execute on function public.mc_list_clans(integer) from public,anon,authenticated;
grant execute on function public.mc_list_clans(integer) to service_role;
revoke execute on function public.mc_get_clan_by_identifier(text) from public,anon,authenticated;
grant execute on function public.mc_get_clan_by_identifier(text) to service_role;