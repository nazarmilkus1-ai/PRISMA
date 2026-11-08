-- Correct the final Iris snapshot/identity mapping and preserve source metadata.
update public.iris_chat_stats_archive
set message_count=9823,source_total=149954
where chat_id=-1003727618185 and snapshot_kind='all_time' and position=2;

update public.iris_chat_stats_archive
set telegram_id=null
where chat_id=-1003727618185 and snapshot_kind='all_time' and position=26;

update public.iris_chat_stats_archive
set telegram_id=8719730740
where chat_id=-1003727618185 and snapshot_kind='all_time' and position=8;

update public.iris_chat_stats_archive
set telegram_id=8378724738
where chat_id=-1003727618185 and snapshot_kind='all_time' and position=35;

update public.iris_chat_stats_archive
set telegram_id=8719730740
where chat_id=-1003727618185 and snapshot_kind='daily' and position=4;

update public.iris_chat_stats_archive
set telegram_id=8378724738
where chat_id=-1003727618185 and snapshot_kind='daily' and position=3;

-- Exact username -> Telegram account mapping for current PRISMA whitelist users.
update public.iris_chat_stats_archive a
set telegram_id=u.telegram_id
from public.users u
where a.chat_id=-1003727618185
  and a.snapshot_kind in ('all_time','daily')
  and a.username is not null
  and a.position <> 26
  and u.status='ACCEPTED'
  and u.is_whitelisted=true
  and u.deleted_at is null
  and lower(u.telegram_username)=lower(a.username);

update public.telegram_chat_activity_legacy l
set message_count=9823,imported_at='2026-09-21 17:07:00+00'
from public.users u
where l.chat_id=-1003727618185 and l.user_id=u.id and u.telegram_id=8285627083;

update public.telegram_chat_history_imports
set source_total_messages=149954,source_daily_messages=1823
where chat_id=-1003727618185 and source='Iris';

alter table public.clans add column if not exists source text;
alter table public.clans add column if not exists source_number integer;
update public.clans set source='Iris',source_number=16 where name='Династия Фараона' and deleted_at is null;
update public.clans set source='Iris',source_number=15 where name='HD' and deleted_at is null;
update public.clans set source='Iris',source_number=9 where name='天堂' and deleted_at is null;

alter table public.iris_clan_import_archive add column if not exists clan_type text default 'open';
alter table public.iris_clan_import_archive add column if not exists reputation integer default 0;
alter table public.iris_clan_import_archive add column if not exists source_member_count integer;
update public.iris_clan_import_archive
set clan_type='open',reputation=0,source_member_count=jsonb_array_length(original_members);

create or replace function public.bot_get_clan_by_position(p_position integer)
returns json language sql security definer set search_path=public as $$
with ranked as (
  select c.*,row_number() over(order by c.rating desc,c.level desc,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
),
picked as (
  select r.* from ranked r
  where r.position=greatest(1,coalesce(p_position,1))
  union all
  select c.*,p_position::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active' and c.source='Iris' and c.source_number=p_position
    and not exists(select 1 from ranked r where r.position=greatest(1,coalesce(p_position,1)))
  limit 1
)
select case when x.id is null then json_build_object('error','CLAN_NOT_FOUND')
else json_build_object(
  'position',x.position,'id',x.id,'name',x.name,'tag',x.tag,'type',x.type,'status',x.status,'owner_id',x.owner_id,
  'description',x.description,'rating',x.rating,'level',x.level,'xp',x.xp,'balance',x.balance,
  'wins',x.wins,'losses',x.losses,'created_at',x.created_at,'source',x.source,'source_number',x.source_number,
  'leader',(select json_build_object('tg_id',u.telegram_id,'username',u.telegram_username,'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname) from public.users u where u.id=x.owner_id),
  'members',coalesce((
    select json_agg(json_build_object('tg_id',u.telegram_id,'username',u.telegram_username,'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname,'role',cm.role,'joined_at',cm.joined_at) order by cm.joined_at)
    from public.clan_members cm join public.users u on u.id=cm.user_id
    where cm.clan_id=x.id and cm.status='active' and u.deleted_at is null
  ),'[]'::json)
) end
from (select * from picked limit 1) x;
$$;

create or replace function public.bot_chat_stats(p_chat_id bigint)
returns json language sql security definer set search_path=public as $$
select json_build_object(
  'total_messages',public.bot_chat_top_total(p_chat_id,null),
  'current_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a join public.users u on u.id=a.user_id where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true),0),
  'legacy_messages',coalesce((select sum(l.message_count)::integer from public.telegram_chat_activity_legacy l join public.users u on u.id=l.user_id where l.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true),0),
  'unique_users',(select count(*)::integer from(
    select a.user_id from public.telegram_chat_activity a join public.users u on u.id=a.user_id where a.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true group by a.user_id
    union
    select l.user_id from public.telegram_chat_activity_legacy l join public.users u on u.id=l.user_id where l.chat_id=p_chat_id and u.deleted_at is null and u.status='ACCEPTED' and u.is_whitelisted=true group by l.user_id
  ) x),
  'source',coalesce((select h.source from public.telegram_chat_history_imports h where h.chat_id=p_chat_id),'PRISMA'),
  'source_total_messages',coalesce((select h.source_total_messages from public.telegram_chat_history_imports h where h.chat_id=p_chat_id),0),
  'source_daily_messages',coalesce((select h.source_daily_messages from public.telegram_chat_history_imports h where h.chat_id=p_chat_id),0)
);
$$;
