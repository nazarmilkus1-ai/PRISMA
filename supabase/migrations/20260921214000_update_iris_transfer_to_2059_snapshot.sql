
-- Latest user-supplied Iris snapshot: 2026-09-21 20:59 Europe/Kyiv (17:59 UTC).
with iris(position,display_name,username,telegram_id,message_count) as (values
(1,'Nastia','na0561',5359447692,16716),
(2,'ало на самом деле дмитрий','xn4zarx',8285627083,9845),
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
(19,'HellDive','holediver',8686232644,900),
(20,'romantic','euvetemens',8240942707,735),
(21,'лех','hellomentoshi',7508802327,729),
(22,'Pabotex - Aquatic Creation','pabotex',6609992582,669),
(23,'IMPERATORVOZDUXAN','bunta_fujiwara_pd',5244257331,663),
(24,'япи дор','eto4l',8096498140,599),
(25,'Atoti','atoti888',5595782593,580),
(26,'Лэфони','lafony',8854954186,514),
(27,'ঔᚢᛋᛟᚺᛊᚹঔ','emperor_of_mace',6470098636,472),
(28,'6248535211',null,6248535211,395),
(29,'ᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟ',null,7930538974,273),
(30,'Yui','zerominx4',7882523618,269),
(31,'Щ3т18С','safebeet319',2030424469,218),
(32,'Pers1k','pers1kq',8596606476,209),
(33,'WERSED','konstant1123',5483851401,197),
(34,'Karlik','andrisol',null,195),
(35,'k1sta',null,8378724738,146),
(36,'Congregation','toyeju',6602798388,144),
(37,'Илья','ra1rka0',null,144),
(38,'Web4ik','web_frogs',7645137936,140),
(39,'foniyachka','foniyachka',null,130),
(40,'Типо ник','tiponik222',5464904752,97),
(41,'SⱧENGENSⱧl','shengenhi',null,77),
(42,'Kosmo_Hub','chei0ve4ek',6679263717,71),
(43,'Хлебушек.exe','kotboss393',8396159014,64),
(44,'Rain PvSheen пожалуйста','facoka',null,56),
(45,'Dr.Kane','dr_kane355',7688381604,40),
(46,'hipvs07','hipvs07',null,32),
(47,'WEEXE','speedwez',7703533065,16),
(48,'D1xxx',null,null,10),
(49,'zoom','thzoom',7809416959,6)
)
update public.iris_chat_stats_archive a
set display_name=i.display_name,
    username=i.username,
    telegram_id=i.telegram_id,
    message_count=i.message_count,
    source_total=149992,
    snapshot_at=timestamptz '2026-09-21 17:59:00+00'
from iris i
where a.chat_id=-1003727618185
  and a.snapshot_kind='all_time'
  and a.position=i.position;

update public.telegram_chat_history_imports
set source='Iris',
    source_total_messages=149992,
    imported_at=timestamptz '2026-09-21 17:59:00+00'
where chat_id=-1003727618185;

update public.telegram_chat_import_state s
set snapshot_at=timestamptz '2026-09-21 17:59:00+00',
    source_total_messages=149992,
    baseline_live_messages=coalesce((select sum(a.message_count)::integer
      from public.telegram_chat_activity a where a.chat_id=-1003727618185),0),
    updated_at=now()
where s.chat_id=-1003727618185;

delete from public.telegram_chat_import_user_baseline
where chat_id=-1003727618185;

insert into public.telegram_chat_import_user_baseline(chat_id,user_id,baseline_live_messages)
select -1003727618185,u.id,
       coalesce(sum(a.message_count),0)::integer
from public.users u
left join public.telegram_chat_activity a
  on a.chat_id=-1003727618185 and a.user_id=u.id
group by u.id;

-- Refresh the user profile snapshot with the latest Iris values supplied in chat.
update public.telegram_chat_profile_snapshot ps
set snapshot_at=timestamptz '2026-09-21 17:59:00+00',
    day_messages=392,
    week_messages=1300,
    month_messages=5200,
    all_messages=9845,
    last_active_at=timestamptz '2026-09-21 17:59:00+00'
where ps.chat_id=-1003727618185
  and ps.user_id=(select u.id from public.users u where u.telegram_id=8285627083);

-- The imported clan descriptions are no longer allowed to claim that their members
-- are missing from PRISMA: the details command now includes the transferred Iris members.
update public.clans
set description = case source_number
  when 9 then 'Импортировано из Iris. Оригинальный №9.'
  when 15 then 'Импортировано из Iris. Оригинальный №15.'
  when 16 then 'Импортировано из Iris. Оригинальный №16.'
  else description
end
where source='Iris' and source_number in (9,15,16);

-- For migrated marriages, keep the exact duration text supplied by Iris.
-- New PRISMA marriages keep their real married_at timestamps.
create or replace function public.bot_list_marriages()
returns json
language sql
security definer
set search_path=public
as $function$
with current_rows as (
  select ia.source_position,
         coalesce(ia.partner_a_tg_id,ua.telegram_id) user_a,
         coalesce(ia.partner_a_name,ua.full_name,ua.telegram_username) user_a_name,
         coalesce(ia.partner_a_username,ua.telegram_username) user_a_username,
         coalesce(ia.partner_b_tg_id,ub.telegram_id) user_b,
         coalesce(ia.partner_b_name,ub.full_name,ub.telegram_username) user_b_name,
         coalesce(ia.partner_b_username,ub.telegram_username) user_b_username,
         case when ia.source_position is not null then null::timestamptz else m.married_at end married_at,
         ia.duration_text,
         ia.green_wedding,
         'ACTIVE'::text status
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  left join public.iris_marriage_import_archive ia
    on ia.chat_id=-1003727618185 and ia.source_position=m.source_position
  where m.status='ACTIVE'
),
historical as (
  select ia.source_position,
         ia.partner_a_tg_id user_a,ia.partner_a_name user_a_name,ia.partner_a_username user_a_username,
         ia.partner_b_tg_id user_b,ia.partner_b_name user_b_name,ia.partner_b_username user_b_username,
         null::timestamptz married_at,ia.duration_text,ia.green_wedding,'ACTIVE'::text status
  from public.iris_marriage_import_archive ia
  where ia.chat_id=-1003727618185
    and not exists(select 1 from current_rows c where c.source_position=ia.source_position)
)
select coalesce(json_agg(r order by r.source_position),'[]'::json)
from (select * from current_rows union all select * from historical) r;
$function$;
