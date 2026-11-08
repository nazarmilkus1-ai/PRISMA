create table if not exists public.iris_chat_stats_archive(
  id uuid primary key default gen_random_uuid(),
  chat_id bigint not null,
  snapshot_kind text not null,
  snapshot_at timestamptz not null,
  position integer,
  display_name text,
  username text,
  telegram_id bigint,
  message_count integer,
  source_total integer,
  imported_at timestamptz not null default now()
);
create unique index if not exists iris_chat_stats_archive_uq
  on public.iris_chat_stats_archive(chat_id,snapshot_kind,position,coalesce(username,''),coalesce(telegram_id,0));
alter table public.iris_chat_stats_archive enable row level security;

create table if not exists public.telegram_chat_daily_snapshot(
  chat_id bigint not null,
  user_id uuid not null references public.users(id) on delete cascade,
  snapshot_date date not null,
  snapshot_at timestamptz not null,
  message_count integer not null,
  primary key(chat_id,user_id,snapshot_date)
);
create table if not exists public.telegram_chat_profile_snapshot(
  chat_id bigint not null,
  user_id uuid not null references public.users(id) on delete cascade,
  snapshot_at timestamptz not null,
  first_seen_at timestamptz,
  last_active_at timestamptz,
  day_messages integer,
  week_messages integer,
  month_messages integer,
  all_messages integer,
  reputation_rating integer,
  reputation_positive integer,
  activity_score integer,
  primary key(chat_id,user_id)
);
alter table public.telegram_chat_daily_snapshot enable row level security;
alter table public.telegram_chat_profile_snapshot enable row level security;

with iris(pos,name,username,message_count) as (values
(1,'Nastia','na0561',16715),(2,'ало на самом деле дмитрий','xn4zarx',9805),(3,'бисмилях','extazysexy',7654),
(4,'ዘꤕተ ዘተꤕ','ignorchiikk',7593),(5,'MKuNDvK','nomfish',6649),(6,'faraon','facenull',4905),
(7,'APTG','aptgsus',4628),(8,'Лэфони',null,4091),(9,'гусь на самом деле человек','alominq',3556),
(10,'хуесос','fantlk',3369),(11,'fckkkgoyim','fckkkgoyim',2547),(12,'Bob','bobminec',2492),
(13,'даня 17/0/0','h1gannn',2254),(14,'назар на самом деле узбек','goose5551803',1862),
(15,'GELZRN','mexahuko',1374),(16,'frisin''ka','fikus_79',1258),(17,'я крут','ffailight',1187),
(18,'Дарья','darix_0',1042),(19,'HellDive','holediver',891),(20,'romantic','euvetemens',735),
(21,'лех','hellomentoshi',729),(22,'Pabotex - Aquatic Creation','pabotex',669),(23,'IMPERATORVOZDUXAN','bunta_fujiwara_pd',663),
(24,'япи дор','eto4l',599),(25,'Atoti','atoti888',580),(26,'Лэфони','lafony',511),
(27,'ঔᚢᛋᛟᚺᛊᚹঔ','emperor_of_mace',472),(28,'6248535211',null,395),
(29,'ᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟᅟ',null,273),
(30,'Yui','zerominx4',269),(31,'Щ3т18С','safebeet319',217),(32,'Pers1k','pers1kq',209),
(33,'WERSED','konstant1123',197),(34,'Karlik','andrisol',195),(35,'k1sta',null,146),
(36,'Congregation','toyeju',144),(37,'Илья','ra1rka0',144),(38,'Web4ik','web_frogs',140),
(39,'foniyachka','foniyachka',130),(40,'Типо ник','tiponik222',97),(41,'SⱧENGENSⱧl','shengenhi',77),
(42,'Kosmo_Hub','chei0ve4ek',71),(43,'Хлебушек.exe','kotboss393',64),(44,'Rain PvSheen пожалуйста','facoka',56),
(45,'Dr.Kane','dr_kane355',40),(46,'hipvs07','hipvs07',32),(47,'WEEXE','speedwez',16),
(48,'D1xxx',null,10),(49,'zoom','thzoom',6))
insert into public.iris_chat_stats_archive(chat_id,snapshot_kind,snapshot_at,position,display_name,username,message_count,source_total)
select -1003727618185,'all_time','2026-09-21 16:39:00+00',pos,name,username,message_count,149939 from iris
on conflict do nothing;

with iris(pos,name,username,message_count) as (values
(1,'faraon','facenull',552),(2,'ало на самом деле дмитрий','xn4zarx',345),(3,'k1sta',null,146),
(4,'Лэфони','lafony',103),(5,'bananaxd','pipisn7',100),(6,'Bob','bobminec',71),(7,'лех','hellomentoshi',66),
(8,'я крут','ffailight',63),(9,'даня 17/0/0','h1gannn',61),(10,'WERSED','konstant1123',45),
(11,'GELZRN','mexahuko',39),(12,'Atoti','atoti888',34),(13,'fckkkgoyim','fckkkgoyim',32),
(14,'Щ3т18С','safebeet319',31),(15,'MKuNDvK','nomfish',24),(16,'IMPERATORVOZDUXAN','bunta_fujiwara_pd',23),
(17,'япи дор','eto4l',22),(18,'бисмилях','extazysexy',17),(19,'D1xxx',null,10),(20,'zoom','thzoom',6),
(21,'Kosmo_Hub','chei0ve4ek',5),(22,'Pabotex - Aquatic Creation','pabotex',3),(23,'Nastia','na0561',3),
(24,'Типо ник','tiponik222',3),(25,'Dr.Kane','dr_kane355',3),(26,'ঔᚢᛋᛟᚺᛊᛟᚺᛊᚹঔ','emperor_of_mace',3),
(27,'хуесос','fantlk',3),(28,'назар на самом деле узбек','goose5551803',3),(29,'гусь на самом деле человек','alominq',2),
(30,'Pers1k','pers1kq',2))
insert into public.iris_chat_stats_archive(chat_id,snapshot_kind,snapshot_at,position,display_name,username,message_count,source_total)
select -1003727618185,'daily','2026-09-21 16:36:00+00',pos,name,username,message_count,1823 from iris
on conflict do nothing;