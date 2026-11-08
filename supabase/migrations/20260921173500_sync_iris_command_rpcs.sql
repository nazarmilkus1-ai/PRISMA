-- Synchronize the final Iris-derived RPCs with the live Supabase state.
alter table public.clans add column if not exists source text;
alter table public.clans add column if not exists source_number integer;

update public.clans set source='Iris',source_number=16 where name='Династия Фараона' and deleted_at is null;
update public.clans set source='Iris',source_number=15 where name='HD' and deleted_at is null;
update public.clans set source='Iris',source_number=9 where name='天堂' and deleted_at is null;

create or replace function public.bot_chat_top(p_chat_id bigint,p_days integer default null,p_limit integer default 10)
returns json language sql security definer set search_path=public as $$
with snap as (
  select s.user_id,u.telegram_id tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         s.message_count::integer messages,s.snapshot_at last_message_at
  from public.telegram_chat_daily_snapshot s join public.users u on u.id=s.user_id
  where s.chat_id=p_chat_id and p_days=1 and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
),
live as (
  select a.user_id,u.telegram_id tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         sum(a.message_count)::integer messages,max(a.last_message_at) last_message_at
  from public.telegram_chat_activity a join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
    and (p_days is null or a.activity_date>=current_date-greatest(0,p_days-1)::integer)
  group by a.user_id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
),
legacy as (
  select l.user_id,u.telegram_id tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         l.message_count::integer messages,l.imported_at last_message_at
  from public.telegram_chat_activity_legacy l join public.users u on u.id=l.user_id
  where l.chat_id=p_chat_id and p_days is null and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
),
combined as (select * from snap union all select * from live union all select * from legacy),
aggregated as (
  select user_id,tg_id,full_name,telegram_username,minecraft_nickname,sum(messages)::integer messages,max(last_message_at) last_message_at
  from combined group by user_id,tg_id,full_name,telegram_username,minecraft_nickname
),
source_names as (
  select distinct on (a.telegram_id) a.telegram_id,a.display_name,a.username
  from public.iris_chat_stats_archive a
  where a.chat_id=p_chat_id and a.snapshot_kind=case when p_days=1 then 'daily' else 'all_time' end and a.telegram_id is not null
  order by a.telegram_id,a.position
)
select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
from (
  select ag.user_id,ag.tg_id,coalesce(sn.display_name,ag.full_name,ag.telegram_username,ag.tg_id::text) full_name,
         nullif(coalesce(sn.username,ag.telegram_username),'') telegram_username,ag.minecraft_nickname,ag.messages,ag.last_message_at,
         sn.display_name source_display_name,sn.username source_username,ag.tg_id source_tg_id
  from aggregated ag left join source_names sn on sn.telegram_id=ag.tg_id
  order by ag.messages desc,ag.last_message_at desc
  limit greatest(1,least(coalesce(p_limit,10),100))
) x;
$$;

create or replace function public.bot_chat_top_total(p_chat_id bigint,p_days integer default null)
returns integer language sql security definer set search_path=public as $$
with base as (
  select a.user_id,sum(a.message_count)::integer n
  from public.telegram_chat_activity a join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
    and (p_days is null or a.activity_date>=current_date-greatest(0,p_days-1)::integer)
  group by a.user_id
),
legacy as (
  select l.user_id,l.message_count::integer n
  from public.telegram_chat_activity_legacy l join public.users u on u.id=l.user_id
  where l.chat_id=p_chat_id and p_days is null and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
),
snap as (
  select s.user_id,s.message_count::integer n
  from public.telegram_chat_daily_snapshot s join public.users u on u.id=s.user_id
  where s.chat_id=p_chat_id and s.snapshot_date=current_date and p_days=1 and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true
),
ids as (select user_id from base union select user_id from legacy union select user_id from snap)
select coalesce(sum(
  coalesce(case when p_days=1 then (select s.n from snap s where s.user_id=ids.user_id)
                else (select l.n from legacy l where l.user_id=ids.user_id) end,0)
  + coalesce((select b.n from base b where b.user_id=ids.user_id),0)
),0)::integer from ids;
$$;

create or replace function public.bot_list_inactive_members(p_days integer,p_limit integer default 50)
returns json language sql security definer set search_path=public as $$
with historical as (
  select s.position,s.display_name,s.username,s.telegram_id,s.last_active_at,s.message_link
  from public.iris_inactive_snapshot s
  where s.chat_id=-1003727618185 and s.last_active_at<now()-make_interval(days=>greatest(1,p_days))
),
live as (
  select a.user_id,max(a.last_message_at) last_seen_at
  from public.telegram_chat_activity a where a.chat_id=-1003727618185 group by a.user_id
),
hist_enriched as (
  select h.position,h.display_name,h.username,h.telegram_id,
         greatest(h.last_active_at,coalesce(l.last_seen_at,'epoch'::timestamptz)) last_seen_at,h.message_link
  from historical h
  left join public.users u on u.telegram_id=h.telegram_id or (h.username is not null and lower(u.telegram_username)=lower(h.username))
  left join live l on l.user_id=u.id
  where l.last_seen_at is null or l.last_seen_at<h.last_active_at
),
current_only as (
  select 1000+row_number() over(order by l.last_seen_at)::integer position,
         coalesce(u.full_name,u.telegram_username,u.telegram_id::text) display_name,u.telegram_username username,u.telegram_id,
         l.last_seen_at,null::text message_link
  from live l join public.users u on u.id=l.user_id
  where u.deleted_at is null and l.last_seen_at<now()-make_interval(days=>greatest(1,p_days))
    and not exists (
      select 1 from public.iris_inactive_snapshot h
      where h.chat_id=-1003727618185 and (h.telegram_id=u.telegram_id or (h.username is not null and lower(h.username)=lower(u.telegram_username)))
    )
),
all_rows as (select * from hist_enriched union all select * from current_only)
select coalesce(json_agg(x order by x.last_seen_at asc),'[]'::json)
from (
  select position,display_name,username,telegram_id,last_seen_at,message_link,
         extract(epoch from(now()-last_seen_at))::bigint age_seconds
  from all_rows order by last_seen_at asc
  limit greatest(1,least(coalesce(p_limit,50),200))
) x;
$$;

create or replace function public.bot_list_clans()
returns json language sql security definer set search_path=public as $$
select coalesce(json_agg(x order by x.rating desc,x.level desc,x.id),'[]'::json)
from (
 select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,c.description,c.type,c.status,c.created_at,c.source,c.source_number,
        owner.telegram_id owner_tg_id,owner.telegram_username owner_username,owner.full_name owner_full_name,
        (select count(*)::integer from public.clan_members cm where cm.clan_id=c.id and cm.status='active') member_count
 from public.clans c left join public.users owner on owner.id=c.owner_id
 where c.deleted_at is null and c.status='active'
 order by c.rating desc,c.level desc,c.id limit 100
) x;
$$;

create or replace function public.bot_list_iris_clan_archive()
returns json language sql security definer set search_path=public as $$
select coalesce(json_agg(x order by x.source_number desc),'[]'::json)
from (
 select source_number,clan_name,leader_name,leader_username,founded_at,original_members,transfer_status
 from public.iris_clan_import_archive
 where source_number not in (
   select source_number from public.clans where source='Iris' and deleted_at is null and source_number is not null
 )
) x;
$$;

create or replace function public.bot_get_iris_clan_by_number(p_number integer)
returns json language sql security definer set search_path=public as $$
select case when x.id is null then json_build_object('error','CLAN_NOT_FOUND')
else json_build_object('position',x.source_number,'name',x.clan_name,'source','Iris','status','ARCHIVED',
  'leader',json_build_object('full_name',x.leader_name,'username',x.leader_username),
  'created_at',x.founded_at,'transfer_status',x.transfer_status,'original_members',x.original_members)
end
from (
 select gen_random_uuid() id,source_number,clan_name,leader_name,leader_username,founded_at,transfer_status,original_members
 from public.iris_clan_import_archive where source_number=p_number limit 1
) x;
$$;

create or replace function public.bot_list_marriages()
returns json language sql security definer set search_path=public as $$
with active as (
 select m.source_position ord,m.source_position,'ACTIVE' status,
        ua.telegram_id user_a,coalesce(ua.full_name,ua.telegram_username) user_a_name,ua.telegram_username user_a_username,
        ub.telegram_id user_b,coalesce(ub.full_name,ub.telegram_username) user_b_name,ub.telegram_username user_b_username,
        m.married_at,false green_wedding,'PRISMA' source,null::text duration_text
 from public.marriages m join public.users ua on ua.id=m.user_a_id join public.users ub on ub.id=m.user_b_id
 where m.status='ACTIVE'
),
archived as (
 select source_position ord,source_position,'ARCHIVED' status,
        partner_a_tg_id user_a,partner_a_name user_a_name,partner_a_username user_a_username,
        partner_b_tg_id user_b,partner_b_name user_b_name,partner_b_username user_b_username,
        null::timestamptz married_at,green_wedding,'Iris' source,duration_text
 from public.iris_marriage_import_archive
 where chat_id=-1003727618185 and source_position not in(select coalesce(source_position,0) from active)
)
select coalesce(json_agg(x order by x.ord),'[]'::json)
from (select * from active union all select * from archived) x;
$$;
