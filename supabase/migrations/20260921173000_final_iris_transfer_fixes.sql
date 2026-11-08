-- Final Iris transfer fixes: exact names/links, inactive snapshot, marriages and clans.
update public.iris_chat_stats_archive
set telegram_id=8719730740
where chat_id=-1003727618185 and snapshot_kind='all_time' and position=8;
update public.iris_chat_stats_archive
set telegram_id=8719730740
where chat_id=-1003727618185 and snapshot_kind='daily' and position=4;
insert into public.telegram_chat_activity_legacy(chat_id,user_id,message_count,source,imported_at)
select -1003727618185,u.id,4091,'IRIS_IMPORT','2026-09-21 16:39:00+00'
from public.users u
where u.telegram_id=8719730740 and u.is_whitelisted=true and u.deleted_at is null
on conflict(chat_id,user_id) do update set
message_count=4091,source='IRIS_IMPORT',imported_at='2026-09-21 16:39:00+00';

create table if not exists public.iris_inactive_snapshot(
  chat_id bigint not null,
  snapshot_at timestamptz not null,
  position integer not null,
  display_name text not null,
  username text,
  telegram_id bigint,
  last_active_at timestamptz not null,
  message_link text,
  inactive_text text,
  primary key(chat_id,position)
);
alter table public.iris_inactive_snapshot enable row level security;

with x(pos,name,username,tg,last_active,link,txt) as (values
(1,'ዘꤕተ ዘተꤕ','ignorchiikk',null,'2026-09-07 14:13:00+00','https://web.telegram.org/k/#5242653070','14 дней 3 ч'),
(2,'Rain PvSheen пожалуйста','facoka',null,'2026-09-14 15:13:00+00','https://web.telegram.org/k/#6265978586','6 дней 22 ч'),
(3,'SⱧENGENSⱧl','shengenhi',null,'2026-09-14 16:13:00+00','https://web.telegram.org/k/#1750462216','6 дней 21 ч'),
(4,'6248535211',null,6248535211,'2026-09-15 11:13:00+00',null,'6 дней 10 ч'),
(5,'Karlik','andrisol',null,'2026-09-16 13:13:00+00','https://web.telegram.org/k/#7504678043','5 дней 8 ч'),
(6,'hipvs07','hipvs07',null,'2026-09-17 12:13:00+00','https://web.telegram.org/k/#2068672005','4 дня 5 ч'),
(7,'8719730740',null,8719730740,'2026-09-17 02:13:00+00',null,'3 дня 19 ч'),
(8,'foniyachka','foniyachka',null,'2026-09-18 08:13:00+00','https://web.telegram.org/k/#5229064197','3 дня 13 ч'),
(9,'frisin''ka','fikus_79',null,'2026-09-18 10:13:00+00','https://web.telegram.org/k/#6177534303','3 дня 11 ч'),
(10,'WEEXE','speedwez',null,'2026-09-18 17:13:00+00','https://web.telegram.org/k/#7703533065','3 дня 4 ч'),
(11,'Илья','ra1rka0',null,'2026-09-18 23:13:00+00','https://web.telegram.org/k/#5115821538','2 дня 22 ч'),
(12,'Хлебушек.exe','kotboss393',null,'2026-09-19 06:13:00+00','https://web.telegram.org/k/#8396159014','2 дня 11 ч'),
(13,'Yui','zerominx4',null,'2026-09-19 07:13:00+00','https://web.telegram.org/k/#7882523618','2 дня 10 ч'),
(14,'Congregation','toyeju',null,'2026-09-19 20:13:00+00','https://web.telegram.org/k/#6602798388','1 день 21 ч'),
(15,'romantic','euvetemens',null,'2026-09-19 22:13:00+00','https://web.telegram.org/k/#8240942707','1 день 19 ч'),
(16,'HellDive','holediver',8686232644,'2026-09-20 09:13:00+00','https://web.telegram.org/k/#8686232644','1 день 8 ч'),
(17,'APTG','aptgsus',1074410422,'2026-09-20 09:13:00+00','https://web.telegram.org/k/#1074410422','1 день 8 ч'),
(18,'Дарья','darix_0',null,'2026-09-20 16:02:00+00','https://web.telegram.org/k/#5253458169','1 день 11 мин')
)
insert into public.iris_inactive_snapshot(chat_id,snapshot_at,position,display_name,username,telegram_id,last_active_at,message_link,inactive_text)
select -1003727618185,'2026-09-21 17:13:00+00',pos,name,username,tg,last_active::timestamptz,link,txt
from x
on conflict(chat_id,position) do update set
snapshot_at=excluded.snapshot_at,display_name=excluded.display_name,username=excluded.username,
telegram_id=excluded.telegram_id,last_active_at=excluded.last_active_at,message_link=excluded.message_link,
inactive_text=excluded.inactive_text;

alter table public.marriages add column if not exists source text;
alter table public.marriages add column if not exists source_position integer;
alter table public.marriages add column if not exists source_green_wedding boolean default false;

create table if not exists public.iris_marriage_import_archive(
  chat_id bigint not null,
  source_position integer not null,
  status text not null default 'ARCHIVED',
  partner_a_name text not null,
  partner_a_username text,
  partner_a_tg_id bigint,
  partner_b_name text not null,
  partner_b_username text,
  partner_b_tg_id bigint,
  duration_text text,
  snapshot_at timestamptz not null,
  green_wedding boolean not null default false,
  primary key(chat_id,source_position)
);
alter table public.iris_marriage_import_archive enable row level security;

with x(pos,a_name,a_user,a_tg,b_name,b_user,b_tg,dur,green) as (values
(1,'MKuNDvK','nomfish',5898676599,'ዘꤕተ ዘተꤕ','ignorchiikk',null,'4 месяца 3 дн',true),
(2,'xNZARx','xn4zarx',8285627083,'Fontanchik','fantlk',6908802383,'28 дней 22 ч',false),
(3,'даня 17/0/0','h1gannn',8202619017,'Yui','zerominx4',7882523618,'28 дней 6 ч',false),
(4,'AL.O','alominq',6677223324,'Goose','goose5551803',8476810893,'12 дней 20 ч',false),
(5,'foniyachka','foniyachka',null,'hipvs07','hipvs07',null,'11 дней 16 ч',false),
(6,'APTG','aptgsus',1074410422,'HellDive','holediver',8686232644,'11 дней 11 ч',false),
(7,'Дарья','darix_0',null,'Великий император|Рельс','bmbrx1',null,'11 дней 10 ч',false),
(8,'Лэфони','lafony',8719730740,'Hai','hellomentoshi',7508802327,'2 дня 19 ч',false),
(9,'Iris | Чат-менеджер','iris_cm_bot',null,'Atoti','atoti888',5595782593,'2 дня 19 ч',false)
)
insert into public.iris_marriage_import_archive(chat_id,source_position,partner_a_name,partner_a_username,partner_a_tg_id,partner_b_name,partner_b_username,partner_b_tg_id,duration_text,snapshot_at,green_wedding)
select -1003727618185,pos,a_name,a_user,a_tg,b_name,b_user,b_tg,dur,'2026-09-21 17:11:00+00',green
from x
on conflict(chat_id,source_position) do update set
partner_a_name=excluded.partner_a_name,partner_a_username=excluded.partner_a_username,partner_a_tg_id=excluded.partner_a_tg_id,
partner_b_name=excluded.partner_b_name,partner_b_username=excluded.partner_b_username,partner_b_tg_id=excluded.partner_b_tg_id,
duration_text=excluded.duration_text,snapshot_at=excluded.snapshot_at,green_wedding=excluded.green_wedding;

update public.marriages m
set source='Iris',source_position=x.pos,source_green_wedding=false
from (values
(2,8285627083::bigint,6908802383::bigint),(3,8202619017::bigint,7882523618::bigint),
(4,6677223324::bigint,8476810893::bigint),(8,8719730740::bigint,7508802327::bigint)
) x(pos,a,b)
join public.users ua on ua.telegram_id=x.a
join public.users ub on ub.telegram_id=x.b
where m.status='ACTIVE'
and ((m.user_a_id=ua.id and m.user_b_id=ub.id) or (m.user_a_id=ub.id and m.user_b_id=ua.id));

update public.marriages m
set married_at=case m.source_position
when 2 then timestamptz '2026-08-23 19:11:00+00'
when 3 then timestamptz '2026-08-24 11:11:00+00'
when 4 then timestamptz '2026-09-08 21:11:00+00'
when 8 then timestamptz '2026-09-18 22:11:00+00' end
where m.source='Iris';

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
  where chat_id=-1003727618185
    and source_position not in (select coalesce(source_position,0) from active)
)
select coalesce(json_agg(x order by x.ord),'[]'::json)
from (select * from active union all select * from archived) x;
$$;

-- Reuse already existing leader rows for the two imported clans and keep only current whitelist members.
update public.clan_members cm
set clan_id=c.id,role='member',status='active',joined_at=date '2026-08-17'
from public.clans c
where c.name='HD' and c.deleted_at is null
  and cm.user_id=(select id from public.users where telegram_id=1074410422 and is_whitelisted=true and deleted_at is null limit 1);
update public.users set clan_id=(select id from public.clans where name='HD' and deleted_at is null limit 1)
where telegram_id=1074410422 and is_whitelisted=true and deleted_at is null;

update public.clan_members cm
set clan_id=c.id,role='member',status='active',joined_at=date '2026-06-09'
from public.clans c
where c.name='天堂' and c.deleted_at is null
  and cm.user_id=(select id from public.users where telegram_id=8476810893 and is_whitelisted=true and deleted_at is null limit 1);
update public.users set clan_id=(select id from public.clans where name='天堂' and deleted_at is null limit 1)
where telegram_id=8476810893 and is_whitelisted=true and deleted_at is null;

update public.telegram_chat_history_imports
set source_total_messages=(
  select sum(message_count)::integer from public.iris_chat_stats_archive
  where chat_id=-1003727618185 and snapshot_kind='all_time'
)
where chat_id=-1003727618185 and source='Iris';
