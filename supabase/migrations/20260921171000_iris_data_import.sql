-- Iris -> PRISMA chat data import.
-- Historical message counts are kept separate so live day/week/month activity remains real.

create table if not exists public.telegram_chat_activity_legacy(
  chat_id bigint not null,
  user_id uuid not null references public.users(id) on delete cascade,
  message_count integer not null default 0,
  source text not null default 'IRIS_IMPORT',
  imported_at timestamptz not null default now(),
  primary key(chat_id,user_id),
  constraint telegram_chat_activity_legacy_count_check check(message_count>=0)
);

alter table public.telegram_chat_activity_legacy enable row level security;

create or replace function public.bot_chat_top(p_chat_id bigint,p_days integer default null,p_limit integer default 10)
returns json language sql security definer set search_path=public as $$
with combined as (
  select a.user_id,u.telegram_id as tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         sum(a.message_count)::integer as messages,max(a.last_message_at) as last_message_at
  from public.telegram_chat_activity a
  join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id
    and (p_days is null or a.activity_date >= current_date-greatest(0,p_days-1)::integer)
    and u.deleted_at is null
  group by a.user_id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
  union all
  select l.user_id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname,
         l.message_count,l.imported_at
  from public.telegram_chat_activity_legacy l
  join public.users u on u.id=l.user_id
  where l.chat_id=p_chat_id and p_days is null and u.deleted_at is null
)
select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
from (
  select user_id,tg_id,full_name,telegram_username,minecraft_nickname,
         sum(messages)::integer messages,max(last_message_at) last_message_at
  from combined
  group by user_id,tg_id,full_name,telegram_username,minecraft_nickname
  order by messages desc,max(last_message_at) desc
  limit greatest(1,least(coalesce(p_limit,10),100))
) x;
$$;

create or replace function public.bot_get_chat_profile_stats(p_chat_id bigint,p_tg_id bigint)
returns json language sql security definer set search_path=public as $$
select case when u.id is null then json_build_object('error','USER_NOT_FOUND')
else json_build_object(
  'tg_id',u.telegram_id,
  'first_seen_at',coalesce((select min(a.first_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),u.community_first_seen_at,u.created_at),
  'last_active_at',coalesce((select max(a.last_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),u.community_last_seen_at,u.last_seen_at,u.created_at),
  'day_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date=current_date),0),
  'week_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-6),0),
  'month_messages',coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-29),0),
  'all_messages',
    coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0)
    + coalesce((select l.message_count from public.telegram_chat_activity_legacy l where l.chat_id=p_chat_id and l.user_id=u.id),0)
) end
from public.users u
where u.telegram_id=p_tg_id and u.deleted_at is null
limit 1;
$$;

create or replace function public.bot_chat_stats(p_chat_id bigint)
returns json language sql security definer set search_path=public as $$
select json_build_object(
  'total_messages',
    coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id),0)
    + coalesce((select sum(l.message_count)::integer from public.telegram_chat_activity_legacy l where l.chat_id=p_chat_id),0),
  'current_messages',
    coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id),0),
  'legacy_messages',
    coalesce((select sum(l.message_count)::integer from public.telegram_chat_activity_legacy l where l.chat_id=p_chat_id),0),
  'unique_users',
    (select count(*)::integer from (
      select a.user_id from public.telegram_chat_activity a where a.chat_id=p_chat_id group by a.user_id
      union
      select l.user_id from public.telegram_chat_activity_legacy l where l.chat_id=p_chat_id group by l.user_id
    ) x)
);
$$;

revoke execute on function public.bot_chat_top(bigint,integer,integer) from public,anon,authenticated;
revoke execute on function public.bot_get_chat_profile_stats(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_chat_stats(bigint) from public,anon,authenticated;
grant execute on function public.bot_chat_top(bigint,integer,integer) to service_role;
grant execute on function public.bot_get_chat_profile_stats(bigint,bigint) to service_role;
grant execute on function public.bot_chat_stats(bigint) to service_role;

with iris(username,message_count) as (values
  ('na0561',16715),('xn4zarx',9808),('extazysexy',7654),('ignorchiikk',7593),('nomfish',6649),
  ('facenull',4905),('aptgsus',4628),('holediver',4091),('alominq',3556),('fantlk',3369),
  ('fckkkgoyim',2547),('bobminec',2492),('h1gannn',2254),('goose5551803',1862),('mexahuko',1374),
  ('fikus_79',1258),('ffailight',1187),('darix_0',1042),('euvetemens',735),('hellomentoshi',729),
  ('pabotex',669),('bunta_fujiwara_pd',663),('eto4l',599),('atoti888',580),('zerominx4',269),
  ('safebeet319',217),('pers1kq',209),('konstant1123',197),('andrisol',195),('k1sta',146),
  ('toyeju',144),('ra1rka0',144),('web_frogs',140),('foniyachka',130),('tiponik222',97),
  ('shengenhi',77),('chei0ve4ek',71),('kotboss393',64),('facoka',56),('dr_kane355',40),
  ('hipvs07',32),('speedwez',16),('thzoom',6)
)
insert into public.telegram_chat_activity_legacy(chat_id,user_id,message_count,source)
select -1003727618185,u.id,i.message_count,'IRIS_IMPORT'
from iris i join public.users u on lower(coalesce(u.telegram_username,''))=lower(i.username)
where u.is_whitelisted=true and u.deleted_at is null
on conflict (chat_id,user_id) do update set message_count=excluded.message_count,source=excluded.source,imported_at=now();

with pairs(a_tg,b_tg,married_at) as (values
  (8285627083::bigint,6908802383::bigint,now()-interval '28 days 22 hours'),
  (8202619017::bigint,7882523618::bigint,now()-interval '28 days 6 hours'),
  (6677223324::bigint,8476810893::bigint,now()-interval '12 days 20 hours'),
  (8719730740::bigint,7508802327::bigint,now()-interval '2 days 19 hours')
), resolved as (
  select least(ua.id,ub.id) user_a_id,greatest(ua.id,ub.id) user_b_id,p.married_at
  from pairs p
  join public.users ua on ua.telegram_id=p.a_tg and ua.is_whitelisted=true and ua.deleted_at is null
  join public.users ub on ub.telegram_id=p.b_tg and ub.is_whitelisted=true and ub.deleted_at is null
)
insert into public.marriages(user_a_id,user_b_id,status,married_at)
select r.user_a_id,r.user_b_id,'ACTIVE',r.married_at from resolved r
where not exists (
  select 1 from public.marriages m where m.status='ACTIVE'
  and (m.user_a_id in (r.user_a_id,r.user_b_id) or m.user_b_id in (r.user_a_id,r.user_b_id))
);

do $$
declare dynasty_id uuid; hd_id uuid; heaven_id uuid;
declare faraon_id uuid; bob_id uuid; aptg_id uuid; goose_id uuid; helldive_id uuid; mku_id uuid;
begin
  select id into faraon_id from public.users where telegram_id=8131532899 and deleted_at is null limit 1;
  select id into bob_id from public.users where telegram_id=8291768799 and is_whitelisted and deleted_at is null limit 1;
  select id into aptg_id from public.users where telegram_id=1074410422 and is_whitelisted and deleted_at is null limit 1;
  select id into goose_id from public.users where telegram_id=8476810893 and is_whitelisted and deleted_at is null limit 1;
  select id into helldive_id from public.users where telegram_id=8686232644 and deleted_at is null limit 1;
  select id into mku_id from public.users where telegram_id=5898676599 and deleted_at is null limit 1;

  if faraon_id is not null and not exists(select 1 from public.clans where name='Династия Фараона' and deleted_at is null) then
    insert into public.clans(name,tag,owner_id,type,status,rating,level,xp,balance,wins,losses,description,created_at,updated_at)
    values('Династия Фараона','DF',faraon_id,'open','active',0,1,0,0,0,0,'Импортировано из Iris. Оригинальный №16.',date '2026-08-19',now())
    returning id into dynasty_id;
    insert into public.clan_members(clan_id,user_id,role,status,joined_at)
    values(dynasty_id,faraon_id,'owner','active',date '2026-08-19'),
          (dynasty_id,bob_id,'member','active',date '2026-08-20')
    on conflict (user_id) do nothing;
    update public.users set clan_id=dynasty_id where id in (faraon_id,bob_id);
  end if;

  if helldive_id is not null and aptg_id is not null and not exists(select 1 from public.clans where name='HD' and deleted_at is null) then
    insert into public.clans(name,tag,owner_id,type,status,rating,level,xp,balance,wins,losses,description,created_at,updated_at)
    values('HD','HD',helldive_id,'open','active',0,1,0,0,0,0,'Импортировано из Iris. Оригинальный №15. Часть участников отсутствует в PRISMA.',date '2026-08-17',now())
    returning id into hd_id;
    insert into public.clan_members(clan_id,user_id,role,status,joined_at)
    values(hd_id,aptg_id,'member','active',date '2026-08-17')
    on conflict (user_id) do nothing;
    update public.users set clan_id=hd_id where id=aptg_id;
  end if;

  if mku_id is not null and goose_id is not null and not exists(select 1 from public.clans where name='天堂' and deleted_at is null) then
    insert into public.clans(name,tag,owner_id,type,status,rating,level,xp,balance,wins,losses,description,created_at,updated_at)
    values('天堂','TIAN',mku_id,'open','active',0,1,0,0,0,0,'Импортировано из Iris. Оригинальный №9. Часть участников отсутствует в PRISMA.',date '2026-06-09',now())
    returning id into heaven_id;
    insert into public.clan_members(clan_id,user_id,role,status,joined_at)
    values(heaven_id,goose_id,'member','active',date '2026-06-09')
    on conflict (user_id) do nothing;
    update public.users set clan_id=heaven_id where id=goose_id;
  end if;
end $$;
