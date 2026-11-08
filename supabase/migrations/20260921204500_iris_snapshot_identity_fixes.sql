-- Latest user-supplied Iris snapshot: 2026-09-21 20:32 Europe/Kyiv (17:32 UTC).

with iris(pos,name,username,tg,message_count) as (values
(1,'Nastia','na0561',5359447692,16716),
(2,'ало на самом деле дмитрий','xn4zarx',8285627083,9831),
(3,'бисмилях','extazysexy',5880980415,7656),
(4,'ዘꤕተ ዘተꤕ','ignorchiikk',null,7593),
(5,'MKuNDvK','nomfish',5898676599,6649),
(6,'faraon','facenull',8131532899,4905),
(7,'APTG','aptgsus',1074410422,4628),
(8,'Лэфони',null,8719730740,4091),
(9,'гусь на самом деле человек','alominq',6677223324,3556),
(10,'хуесос','fantlk',6908802383,3369),
(11,'fckkkgoyim','fckkkgoyim',5268142003,2547),
(12,'Bob','bobminec',8291768799,2492),
(13,'даня 17/0/0','h1gannn',8202619017,2254),
(14,'назар на самом деле узбек','goose5551803',8476810893,1862),
(15,'GELZRN','mexahuko',6495718104,1374),
(16,'frisin''ka','fikus_79',null,1258),
(17,'я крут','ffailight',8967645293,1188),
(18,'Дарья','darix_0',5253458169,1042),
(19,'HellDive','holediver',8686232644,897),
(20,'romantic','euvetemens',8240942707,735),
(21,'лех','hellomentoshi',7508802327,729),
(22,'Pabotex - Aquatic Creation','pabotex',6609992582,669),
(23,'IMPERATORVOZDUXAN','bunta_fujiwara_pd',5244257331,663),
(24,'япи дор','eto4l',8096498140,599),
(25,'Atoti','atoti888',5595782593,580),
(26,'Лэфони','lafony',8854954186,514),
(27,'ঔᚢᛋᛟᚺᛊᚹঔ','emperor_of_mace',6470098636,472),
(28,'6248535211',null,6248535211,395),
(29,repeat(chr(4447),21),null,7930538974,273),
(30,'Yui','zerominx4',7882523618,269)
)
update public.iris_chat_stats_archive a
set display_name=i.name,username=i.username,telegram_id=i.tg,message_count=i.message_count,
    source_total=149974,snapshot_at=timestamptz '2026-09-21 17:32:00+00'
from iris i
where a.chat_id=-1003727618185 and a.snapshot_kind='all_time' and a.position=i.pos;

update public.telegram_chat_history_imports
set source_total_messages=149974
where chat_id=-1003727618185 and source='Iris';

create table if not exists public.iris_nickname_import_archive(
  chat_id bigint not null,
  source_position integer not null,
  display_name text not null,
  username text,
  telegram_id bigint,
  nickname text not null,
  profile_link text,
  snapshot_at timestamptz not null,
  primary key(chat_id,source_position)
);
alter table public.iris_nickname_import_archive enable row level security;

with x(pos,name,username,tg,nickname,link) as (values
(1,'бисмилях','extazysexy',5880980415,'misanthropy','https://t.me/extazysexy'),
(2,'ало на самом деле дмитрий','xn4zarx',8285627083,'xNZARx','https://t.me/xn4zarx'),
(3,'назар на самом деле узбек','goose5551803',8476810893,'Goose','https://t.me/goose5551803'),
(4,'гусь на самом деле человек','alominq',6677223324,'AL.O','https://t.me/alominq'),
(5,'Лэфони',null,8719730740,'8719730740','tg://openmessage?user_id=8719730740'),
(6,'хуесос','fantlk',6908802383,'Fontanchik','https://t.me/fantlk'),
(7,'Щ3т18С','safebeet319',2030424469,'Bratish','https://t.me/safebeet319'),
(8,'я крут','ffailight',8967645293,'rarar','https://t.me/ffailight'),
(9,'япи дор','eto4l',8096498140,'Squzix','https://t.me/eto4l'),
(10,'лех','hellomentoshi',7508802327,'Hai','https://t.me/hellomentoshi')
)
insert into public.iris_nickname_import_archive(
  chat_id,source_position,display_name,username,telegram_id,nickname,profile_link,snapshot_at
)
select -1003727618185,pos,name,username,tg,nickname,link,timestamptz '2026-09-21 17:32:00+00'
from x
on conflict(chat_id,source_position) do update set
  display_name=excluded.display_name,username=excluded.username,telegram_id=excluded.telegram_id,
  nickname=excluded.nickname,profile_link=excluded.profile_link,snapshot_at=excluded.snapshot_at;

create or replace function public.bot_list_iris_nicknames()
returns json language sql security definer set search_path=public as $$
select coalesce(json_agg(x order by x.source_position),'[]'::json)
from (
  select source_position,display_name,username,telegram_id,nickname,profile_link
  from public.iris_nickname_import_archive
  where chat_id=-1003727618185
) x;
$$;

revoke execute on function public.bot_list_iris_nicknames() from public,anon,authenticated;
grant execute on function public.bot_list_iris_nicknames() to service_role;


create or replace function public.bot_list_iris_inactive_snapshot()
returns json language sql security definer set search_path=public as $$
select coalesce(json_agg(x order by x.position),'[]'::json)
from (
  select position,display_name,username,telegram_id,last_active_at,message_link,inactive_text
  from public.iris_inactive_snapshot
  where chat_id=-1003727618185
) x;
$$;

revoke execute on function public.bot_list_iris_inactive_snapshot() from public,anon,authenticated;
grant execute on function public.bot_list_iris_inactive_snapshot() to service_role;

create or replace function public.bot_list_clans()
returns json language sql security definer set search_path=public as $$
select coalesce(json_agg(x order by x.rating desc,x.level desc,x.id),'[]'::json)
from (
 select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,c.description,c.type,c.status,c.created_at,c.source,c.source_number,
        owner.telegram_id owner_tg_id,
        coalesce(ia.leader_username,owner.telegram_username) owner_username,
        coalesce(ia.leader_name,owner.full_name) owner_full_name,
        (select count(*)::integer from public.clan_members cm where cm.clan_id=c.id and cm.status='active') member_count
 from public.clans c
 left join public.users owner on owner.id=c.owner_id
 left join public.iris_clan_import_archive ia on ia.source_number=c.source_number
 where c.deleted_at is null and c.status='active'
 order by c.rating desc,c.level desc,c.id
 limit 100
) x;
$$;

create or replace function public.bot_list_marriages()
returns json language sql security definer set search_path=public as $$
with active as (
  select m.source_position ord,m.source_position,'ACTIVE' status,
         coalesce(ia.partner_a_tg_id,ua.telegram_id) user_a,
         coalesce(ia.partner_a_name,coalesce(ua.full_name,ua.telegram_username)) user_a_name,
         coalesce(ia.partner_a_username,ua.telegram_username) user_a_username,
         coalesce(ia.partner_b_tg_id,ub.telegram_id) user_b,
         coalesce(ia.partner_b_name,coalesce(ub.full_name,ub.telegram_username)) user_b_name,
         coalesce(ia.partner_b_username,ub.telegram_username) user_b_username,
         m.married_at,false green_wedding,'PRISMA' source,null::text duration_text
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  left join public.iris_marriage_import_archive ia
    on ia.chat_id=-1003727618185 and ia.source_position=m.source_position
  where m.status='ACTIVE'
),
archived as (
  select source_position ord,source_position,'ARCHIVED' status,
         partner_a_tg_id user_a,partner_a_name user_a_name,partner_a_username user_a_username,
         partner_b_tg_id user_b,partner_b_name user_b_name,partner_b_username user_b_username,
         null::timestamptz married_at,green_wedding,'Iris' source,duration_text
  from public.iris_marriage_import_archive
  where chat_id=-1003727618185
    and source_position not in(select coalesce(source_position,0) from active)
)
select coalesce(json_agg(x order by x.ord),'[]'::json)
from (select * from active union all select * from archived) x;
$$;
