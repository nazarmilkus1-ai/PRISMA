create or replace function public.bot_list_clans()
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.rating desc,x.level desc,x.name),'[]'::json)
from (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.wins,c.losses,c.description,c.type,c.status,c.created_at,
         owner.telegram_id owner_tg_id,owner.telegram_username owner_username,owner.full_name owner_full_name,
         coalesce((select count(*)::integer from public.clan_members cm
                   where cm.clan_id=c.id and cm.status='active'),0) member_count
  from public.clans c
  left join public.users owner on owner.id=c.owner_id
  where c.deleted_at is null and c.status='active'
) x;
$function$;

create or replace function public.bot_get_clan_by_position(p_position integer)
returns json
language sql stable security definer set search_path=''
as $function$
with ranked as (
  select c.*,row_number() over(order by c.rating desc,c.level desc,c.name,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
),
selected as (
  select r.*,owner.telegram_id owner_tg_id,owner.telegram_username owner_username,
         owner.full_name owner_full_name,owner.minecraft_nickname owner_minecraft_nickname
  from ranked r left join public.users owner on owner.id=r.owner_id
  where r.position=greatest(1,coalesce(p_position,1))
)
select case
  when s.id is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',s.position,'id',s.id,'name',s.name,'tag',coalesce(s.tag,''),'type',s.type,'status',s.status,
    'owner_id',s.owner_id,'description',s.description,'rating',s.rating,'level',s.level,'xp',s.xp,
    'wins',s.wins,'losses',s.losses,'created_at',s.created_at,'is_imported',false,
    'leader',json_build_object('tg_id',s.owner_tg_id,'username',s.owner_username,
      'full_name',s.owner_full_name,'minecraft_nick',s.owner_minecraft_nickname),
    'members',coalesce((
      select json_agg(json_build_object(
        'tg_id',u.telegram_id,'username',u.telegram_username,'full_name',u.full_name,
        'minecraft_nick',u.minecraft_nickname,'role',cm.role,'joined_at',cm.joined_at
      ) order by case cm.role when 'owner' then 0 when 'co_owner' then 1
          when 'officer' then 2 when 'member' then 3 when 'recruit' then 4 else 5 end,
        cm.joined_at,u.minecraft_nickname)
      from public.clan_members cm join public.users u on u.id=cm.user_id
      where cm.clan_id=s.id and cm.status='active' and u.deleted_at is null
    ),'[]'::json)
  )
end from selected s;
$function$;

create or replace function public.mc_get_clan_context(p_user_id uuid)
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce((
  select json_build_object(
    'clan_id',c.id,'name',c.name,'tag',c.tag,'owner_id',c.owner_id,
    'rating',c.rating,'level',c.level,'xp',c.xp,'wins',c.wins,'losses',c.losses,
    'member_role',cm.role
  )
  from public.clan_members cm
  join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active'
    and c.deleted_at is null and c.status='active'
  limit 1
),'{}'::json);
$function$;

revoke execute on function public.bot_list_clans() from public,anon,authenticated;
grant execute on function public.bot_list_clans() to service_role;
revoke execute on function public.bot_get_clan_by_position(integer) from public,anon,authenticated;
grant execute on function public.bot_get_clan_by_position(integer) to service_role;
revoke execute on function public.mc_get_clan_context(uuid) from public,anon,authenticated;
grant execute on function public.mc_get_clan_context(uuid) to service_role;
