create or replace function public.bot_get_chat_profile_stats(p_chat_id bigint,p_tg_id bigint)
returns json language sql security definer set search_path=public as $$
select case
  when u.id is null then json_build_object('error','USER_NOT_FOUND')
  else json_build_object(
    'tg_id',u.telegram_id,
    'first_seen_at',coalesce(
      (select min(a.first_message_at) from public.telegram_chat_activity a
       where a.chat_id=p_chat_id and a.user_id=u.id),
      u.community_first_seen_at,u.created_at
    ),
    'last_active_at',coalesce(
      (select max(a.last_message_at) from public.telegram_chat_activity a
       where a.chat_id=p_chat_id and a.user_id=u.id),
      u.community_last_seen_at,u.last_seen_at,u.created_at
    ),
    'day_messages',coalesce((
      select sum(a.message_count)::integer from public.telegram_chat_activity a
      where a.chat_id=p_chat_id and a.user_id=u.id
        and a.activity_date=current_date
    ),0),
    'week_messages',coalesce((
      select sum(a.message_count)::integer from public.telegram_chat_activity a
      where a.chat_id=p_chat_id and a.user_id=u.id
        and a.activity_date>=current_date-6
    ),0),
    'month_messages',coalesce((
      select sum(a.message_count)::integer from public.telegram_chat_activity a
      where a.chat_id=p_chat_id and a.user_id=u.id
        and a.activity_date>=current_date-29
    ),0),
    'all_messages',coalesce((
      select sum(a.message_count)::integer from public.telegram_chat_activity a
      where a.chat_id=p_chat_id and a.user_id=u.id
    ),0)
  )
end
from public.users u
where u.telegram_id=p_tg_id and u.deleted_at is null
limit 1;
$$;

create or replace function public.bot_get_clan_by_position(p_position integer)
returns json language sql security definer set search_path=public as $$
with ranked as (
  select c.*,
         row_number() over(order by c.rating desc,c.level desc,c.id)::integer as position
  from public.clans c
  where c.deleted_at is null and c.status='active'
)
select case
  when r.id is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',r.position,'id',r.id,'name',r.name,'tag',r.tag,'type',r.type,'status',r.status,
    'owner_id',r.owner_id,'description',r.description,'rating',r.rating,'level',r.level,'xp',r.xp,
    'balance',r.balance,'wins',r.wins,'losses',r.losses,'created_at',r.created_at,
    'leader',(
      select json_build_object('tg_id',u.telegram_id,'username',u.telegram_username,
                               'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname)
      from public.users u where u.id=r.owner_id
    ),
    'members',coalesce((
      select json_agg(json_build_object(
        'tg_id',u.telegram_id,'username',u.telegram_username,'full_name',u.full_name,
        'minecraft_nick',u.minecraft_nickname,'role',cm.role,'joined_at',cm.joined_at
      ) order by cm.joined_at)
      from public.clan_members cm
      join public.users u on u.id=cm.user_id
      where cm.clan_id=r.id and cm.status='active' and u.deleted_at is null
    ),'[]'::json)
  )
end
from ranked r
where r.position=greatest(1,coalesce(p_position,1))
limit 1;
$$;

create or replace function public.bot_list_clans()
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.rating desc,x.level desc,x.id),'[]'::json)
 from (
   select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,c.description,
          c.type,c.status,c.created_at,
          owner.telegram_id as owner_tg_id,
          owner.telegram_username as owner_username,
          owner.full_name as owner_full_name,
          (select count(*)::integer from public.clan_members cm
           where cm.clan_id=c.id and cm.status='active') as member_count
   from public.clans c
   left join public.users owner on owner.id=c.owner_id
   where c.deleted_at is null and c.status='active'
   order by c.rating desc,c.level desc,c.id
   limit 100
 ) x;
$$;

revoke execute on function public.bot_get_chat_profile_stats(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_get_clan_by_position(integer) from public,anon,authenticated;
revoke execute on function public.bot_list_clans() from public,anon,authenticated;

grant execute on function public.bot_get_chat_profile_stats(bigint,bigint) to service_role;
grant execute on function public.bot_get_clan_by_position(integer) to service_role;
grant execute on function public.bot_list_clans() to service_role;
