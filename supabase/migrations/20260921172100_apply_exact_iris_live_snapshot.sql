
-- Apply the exact Iris snapshot used by the live PRISMA chat.
with iris(username,message_count) as (values
('facenull',552),('xn4zarx',345),('bobminec',71),('hellomentoshi',66),('ffailight',63),
('h1gannn',61),('konstant1123',45),('mexahuko',39),('atoti888',34),('fckkkgoyim',32),
('safebeet319',31),('bunta_fujiwara_pd',23),('eto4l',22),('chei0ve4ek',5),
('na0561',3),('dr_kane355',3),('fantlk',3),('goose5551803',3),('alominq',2)
)
insert into public.telegram_chat_daily_snapshot(chat_id,user_id,snapshot_date,snapshot_at,message_count)
select -1003727618185,u.id,date '2026-09-21','2026-09-21 16:36:00+00',i.message_count
from iris i
join public.users u on lower(coalesce(u.telegram_username,''))=lower(i.username)
where u.is_whitelisted=true and u.deleted_at is null
on conflict(chat_id,user_id,snapshot_date) do update
set snapshot_at=excluded.snapshot_at,message_count=excluded.message_count;

insert into public.telegram_chat_profile_snapshot
(chat_id,user_id,snapshot_at,first_seen_at,last_active_at,day_messages,week_messages,month_messages,all_messages,reputation_rating,reputation_positive,activity_score)
select -1003727618185,id,'2026-09-21 16:40:00+00','2026-07-13 00:00:00+00','2026-09-21 16:40:00+00',
       360,1300,5200,9808,0,7,7
from public.users
where telegram_id=8285627083 and deleted_at is null
on conflict(chat_id,user_id) do update set
 snapshot_at=excluded.snapshot_at,first_seen_at=excluded.first_seen_at,last_active_at=excluded.last_active_at,
 day_messages=excluded.day_messages,week_messages=excluded.week_messages,month_messages=excluded.month_messages,
 all_messages=excluded.all_messages,reputation_rating=excluded.reputation_rating,
 reputation_positive=excluded.reputation_positive,activity_score=excluded.activity_score;

delete from public.telegram_chat_activity
where chat_id=-1003727618185 and activity_date=date '2026-09-21';

update public.users
set clan_id=null,updated_at=now()
where id in (
  select cm.user_id from public.clan_members cm
  join public.clans c on c.id=cm.clan_id
  where c.name in ('HD','天堂') and c.deleted_at is null
);

update public.clan_members
set status='left'
where clan_id in (
  select id from public.clans where name in ('HD','天堂') and deleted_at is null
);

update public.clans
set status='deleted',deleted_at=now(),updated_at=now()
where name in ('HD','天堂') and deleted_at is null;
