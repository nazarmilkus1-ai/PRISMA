create or replace function public.bot_list_clans()
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.rating desc,x.level desc,x.name), '[]'::json)
from (
  select
    c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,
    c.description,c.type,c.status,c.created_at,
    owner.telegram_id owner_tg_id,
    owner.telegram_username owner_username,
    owner.full_name owner_full_name,
    coalesce((
      select count(*)::integer from public.clan_members cm
      where cm.clan_id=c.id and cm.status='active'
    ),0) member_count,
    false is_imported
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
  select
    c.*,
    row_number() over(order by c.rating desc,c.level desc,c.name,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
),
selected as (
  select r.*,owner.telegram_id owner_tg_id,owner.telegram_username owner_username,
         owner.full_name owner_full_name,owner.minecraft_nickname owner_minecraft_nickname
  from ranked r
  left join public.users owner on owner.id=r.owner_id
  where r.position=greatest(1,coalesce(p_position,1))
)
select case
  when s.id is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',s.position,'id',s.id,'name',s.name,'tag',coalesce(s.tag,''),
    'type',s.type,'status',s.status,'owner_id',s.owner_id,
    'description',s.description,'rating',s.rating,'level',s.level,'xp',s.xp,
    'balance',s.balance,'wins',s.wins,'losses',s.losses,'created_at',s.created_at,
    'is_imported',false,
    'leader',json_build_object(
      'tg_id',s.owner_tg_id,'username',s.owner_username,
      'full_name',s.owner_full_name,'minecraft_nick',s.owner_minecraft_nickname
    ),
    'members',coalesce((
      select json_agg(
        json_build_object(
          'tg_id',u.telegram_id,'username',u.telegram_username,
          'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname,
          'role',cm.role,'joined_at',cm.joined_at
        )
        order by case cm.role
          when 'owner' then 0 when 'co_owner' then 1 when 'officer' then 2
          when 'member' then 3 when 'recruit' then 4 else 5 end,
          cm.joined_at,u.minecraft_nickname
      )
      from public.clan_members cm
      join public.users u on u.id=cm.user_id
      where cm.clan_id=s.id and cm.status='active' and u.deleted_at is null
    ),'[]'::json)
  )
end
from selected s;
$function$;

create or replace function public.bot_chat_top(
  p_chat_id bigint,p_days integer default null,p_limit integer default 10
)
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
from (
  select
    u.id user_id,
    u.telegram_id tg_id,
    u.full_name,
    u.telegram_username,
    u.minecraft_nickname,
    sum(a.message_count)::integer messages,
    max(a.last_message_at) last_message_at,
    u.full_name source_display_name,
    u.telegram_username source_username,
    u.telegram_id source_tg_id
  from public.telegram_chat_activity a
  join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id
    and (p_days is null or a.activity_date>=current_date-greatest(0,p_days-1))
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and u.is_whitelisted and not u.is_banned
  group by u.id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
  having sum(a.message_count)>0
  order by messages desc,last_message_at desc
  limit greatest(1,least(coalesce(p_limit,10),100))
) x;
$function$;

create or replace function public.bot_chat_top_total(
  p_chat_id bigint,p_days integer default null
)
returns integer
language sql stable security definer set search_path=''
as $function$
select coalesce(sum(a.message_count),0)::integer
from public.telegram_chat_activity a
join public.users u on u.id=a.user_id
where a.chat_id=p_chat_id
  and (p_days is null or a.activity_date>=current_date-greatest(0,p_days-1))
  and u.deleted_at is null
  and u.status='ACCEPTED'::public.application_status
  and u.is_whitelisted and not u.is_banned;
$function$;

create or replace function public.bot_chat_stats(p_chat_id bigint)
returns json
language sql stable security definer set search_path=''
as $function$
select json_build_object(
  'total_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a join public.users u on u.id=a.user_id where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and u.is_whitelisted and not u.is_banned),0),
  'current_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a join public.users u on u.id=a.user_id where a.chat_id=p_chat_id and a.activity_date=current_date and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and u.is_whitelisted and not u.is_banned),0),
  'legacy_messages',0,
  'unique_users',coalesce((select count(distinct a.user_id)::integer from public.telegram_chat_activity a join public.users u on u.id=a.user_id where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and u.is_whitelisted and not u.is_banned),0),
  'source','PRISMA',
  'source_total_messages',0,
  'source_snapshot_at',null
);
$function$;

create or replace function public.bot_get_chat_profile_stats(p_chat_id bigint,p_tg_id bigint)
returns json
language sql stable security definer set search_path=''
as $function$
select case
  when u.id is null then json_build_object('error','USER_NOT_FOUND')
  else json_build_object(
    'tg_id',u.telegram_id,
    'first_seen_at',coalesce(
      (select min(a.first_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),
      u.community_first_seen_at,u.created_at
    ),
    'last_active_at',coalesce(
      (select max(a.last_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),
      u.last_seen_at,u.created_at
    ),
    'day_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date=current_date),0),
    'week_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-6),0),
    'month_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-29),0),
    'all_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0),
    'reputation_rating',coalesce(u.rating,0),
    'reputation_positive',0,
    'activity_score',coalesce(u.activity_score,0)
  )
end
from public.users u
where u.telegram_id=p_tg_id and u.deleted_at is null
limit 1;
$function$;

create or replace function public.bot_list_inactive_members(p_days integer,p_limit integer default 50)
returns json
language sql stable security definer set search_path=''
as $function$
with activity as (
  select a.user_id,max(a.last_message_at) last_seen_at
  from public.telegram_chat_activity a
  where a.chat_id=-1003727618185
  group by a.user_id
),
users_current as (
  select
    u.id,
    coalesce(a.last_seen_at,u.last_seen_at,u.created_at) last_seen_at,
    coalesce(u.full_name,u.telegram_username,u.minecraft_nickname,u.telegram_id::text) display_name,
    u.telegram_username username,
    u.telegram_id
  from public.users u
  left join activity a on a.user_id=u.id
  where u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and u.is_whitelisted=true
    and not u.is_banned
    and coalesce(a.last_seen_at,u.last_seen_at,u.created_at)
      < now()-make_interval(days=>greatest(1,coalesce(p_days,1)))
)
select coalesce(json_agg(x order by x.last_seen_at asc),'[]'::json)
from (
  select
    row_number() over(order by last_seen_at asc)::integer position,
    display_name,username,telegram_id,last_seen_at,null::text message_link,
    extract(epoch from (now()-last_seen_at))::bigint age_seconds
  from users_current
  order by last_seen_at asc
  limit greatest(1,least(coalesce(p_limit,50),200))
) x;
$function$;

create or replace function public.bot_list_marriages()
returns json
language sql stable security definer set search_path=''
as $function$
select coalesce(json_agg(x order by x.married_at asc),'[]'::json)
from (
  select
    m.user_a_id,m.user_b_id,
    ua.telegram_id user_a,
    coalesce(ua.full_name,ua.telegram_username,ua.minecraft_nickname) user_a_name,
    ua.telegram_username user_a_username,
    ub.telegram_id user_b,
    coalesce(ub.full_name,ub.telegram_username,ub.minecraft_nickname) user_b_name,
    ub.telegram_username user_b_username,
    m.married_at,m.divorced_at,
    null::text duration_text,
    false green_wedding,
    'ACTIVE'::text status
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  where m.status='ACTIVE'
    and ua.deleted_at is null and ub.deleted_at is null
) x;
$function$;

revoke execute on function public.bot_list_clans() from public,anon,authenticated;
grant execute on function public.bot_list_clans() to service_role;
revoke execute on function public.bot_get_clan_by_position(integer) from public,anon,authenticated;
grant execute on function public.bot_get_clan_by_position(integer) to service_role;
revoke execute on function public.bot_chat_top(bigint,integer,integer) from public,anon,authenticated;
grant execute on function public.bot_chat_top(bigint,integer,integer) to service_role;
revoke execute on function public.bot_chat_top_total(bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_chat_top_total(bigint,integer) to service_role;
revoke execute on function public.bot_chat_stats(bigint) from public,anon,authenticated;
grant execute on function public.bot_chat_stats(bigint) to service_role;
revoke execute on function public.bot_get_chat_profile_stats(bigint,bigint) from public,anon,authenticated;
grant execute on function public.bot_get_chat_profile_stats(bigint,bigint) to service_role;
revoke execute on function public.bot_list_inactive_members(integer,integer) from public,anon,authenticated;
grant execute on function public.bot_list_inactive_members(integer,integer) to service_role;
revoke execute on function public.bot_list_marriages() from public,anon,authenticated;
grant execute on function public.bot_list_marriages() to service_role;

drop function if exists public.bot_list_iris_clan_archive();
drop function if exists public.bot_get_iris_clan_by_number(integer);
