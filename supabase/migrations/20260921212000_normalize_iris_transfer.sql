
-- Normalize Iris transfer into the normal PRISMA data flow.
-- Snapshot supplied by the user: 2026-09-21 20:45 Europe/Kyiv (17:45 UTC).

create table if not exists public.telegram_chat_import_state (
  chat_id bigint primary key,
  source text not null,
  snapshot_at timestamptz not null,
  source_total_messages integer not null default 0,
  baseline_live_messages integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.telegram_chat_import_state enable row level security;

create table if not exists public.telegram_chat_import_user_baseline (
  chat_id bigint not null,
  user_id uuid not null references public.users(id) on delete cascade,
  baseline_live_messages integer not null default 0,
  primary key(chat_id,user_id)
);
alter table public.telegram_chat_import_user_baseline enable row level security;

-- Exact latest Iris all-time snapshot from the user.
with iris(position,display_name,username,telegram_id,message_count) as (values
(1,'Nastia','na0561',5359447692,16716),
(2,'ало на самом деле дмитрий','xn4zarx',8285627083,9842),
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
(31,'Щ3т18С','safebeet319',2030424469,217),
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
    source_total=149988,
    snapshot_at=timestamptz '2026-09-21 17:45:00+00'
from iris i
where a.chat_id=-1003727618185
  and a.snapshot_kind='all_time'
  and a.position=i.position;

update public.telegram_chat_history_imports
set source='Iris',
    source_total_messages=149988,
    imported_at=timestamptz '2026-09-21 17:45:00+00'
where chat_id=-1003727618185;

insert into public.telegram_chat_import_state(chat_id,source,snapshot_at,source_total_messages,baseline_live_messages,updated_at)
select -1003727618185,'Iris',timestamptz '2026-09-21 17:45:00+00',149988,
       coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=-1003727618185),0),
       now()
on conflict(chat_id) do update set
  source=excluded.source,
  snapshot_at=excluded.snapshot_at,
  source_total_messages=excluded.source_total_messages,
  baseline_live_messages=excluded.baseline_live_messages,
  updated_at=now();

delete from public.telegram_chat_import_user_baseline
where chat_id=-1003727618185;

insert into public.telegram_chat_import_user_baseline(chat_id,user_id,baseline_live_messages)
select -1003727618185,u.id,
       coalesce(sum(a.message_count),0)::integer
from public.users u
left join public.telegram_chat_activity a
  on a.chat_id=-1003727618185 and a.user_id=u.id
group by u.id;

-- All-time top: exact Iris snapshot + only messages written after the transfer baseline.
create or replace function public.bot_chat_top(p_chat_id bigint, p_days integer default null, p_limit integer default 10)
returns json
language sql
security definer
set search_path=public
as $function$
with imported as (
  select s.position,s.display_name,s.username,s.telegram_id,s.message_count,s.snapshot_at
  from public.iris_chat_stats_archive s
  where s.chat_id=p_chat_id
    and s.snapshot_kind='all_time'
    and p_days is null
),
resolved as (
  select i.*,
         u.id as user_id,
         coalesce((select sum(a.message_count)::integer
                   from public.telegram_chat_activity a
                   where a.chat_id=p_chat_id and a.user_id=u.id),0) as live_messages
  from imported i
  left join lateral (
    select u0.id
    from public.users u0
    where u0.deleted_at is null
      and (
        (i.telegram_id is not null and u0.telegram_id=i.telegram_id)
        or
        (i.telegram_id is null and nullif(i.username,'') is not null
         and lower(coalesce(u0.telegram_username,''))=lower(i.username))
      )
    order by case when i.telegram_id is not null and u0.telegram_id=i.telegram_id then 0 else 1 end,
             u0.is_whitelisted desc,
             u0.created_at asc
    limit 1
  ) u on true
),
imported_rows as (
  select r.position,r.display_name,r.username,r.telegram_id,
         r.message_count
           + greatest(
               0,
               r.live_messages-coalesce(b.baseline_live_messages,0)
             ) as messages,
         r.snapshot_at as last_message_at,
         r.display_name as source_display_name,
         r.username as source_username,
         r.telegram_id as source_tg_id
  from resolved r
  left join public.telegram_chat_import_user_baseline b
    on b.chat_id=p_chat_id and b.user_id=r.user_id
),
live as (
  select u.id as user_id,
         u.telegram_id as tg_id,
         u.full_name,
         u.telegram_username,
         sum(a.message_count)::integer as live_messages,
         max(a.last_message_at) as last_message_at
  from public.telegram_chat_activity a
  join public.users u on u.id=a.user_id
  where a.chat_id=p_chat_id
    and u.deleted_at is null
  group by u.id,u.telegram_id,u.full_name,u.telegram_username
),
live_only as (
  select null::integer as position,
         l.full_name as display_name,
         l.telegram_username as username,
         l.tg_id as telegram_id,
         greatest(0,l.live_messages-coalesce(b.baseline_live_messages,0))::integer as messages,
         l.last_message_at,
         null::text as source_display_name,
         null::text as source_username,
         null::bigint as source_tg_id
  from live l
  left join public.telegram_chat_import_user_baseline b
    on b.chat_id=p_chat_id and b.user_id=l.user_id
  where not exists (
    select 1
    from resolved r
    where r.user_id=l.user_id
  )
),
all_rows as (
  select * from imported_rows
  union all
  select * from live_only
)
select coalesce(json_agg(x order by x.messages desc,x.position nulls last,x.last_message_at desc),'[]'::json)
from (
  select *
  from all_rows
  where messages > 0
  order by messages desc,position nulls last,last_message_at desc
  limit greatest(1,least(coalesce(p_limit,10),100))
) x
where p_days is null

union all

select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
from (
  with live_period as (
    select a.user_id,u.telegram_id tg_id,u.full_name,u.telegram_username,u.minecraft_nickname,
           sum(a.message_count)::integer messages,max(a.last_message_at) last_message_at
    from public.telegram_chat_activity a
    join public.users u on u.id=a.user_id
    where a.chat_id=p_chat_id
      and (p_days is null or a.activity_date >= current_date-greatest(0,p_days-1)::integer)
      and u.deleted_at is null
    group by a.user_id,u.telegram_id,u.full_name,u.telegram_username,u.minecraft_nickname
  )
  select lp.user_id,lp.tg_id,lp.full_name,lp.telegram_username,lp.minecraft_nickname,
         lp.messages,lp.last_message_at,null::text source_display_name,
         null::text source_username,null::bigint source_tg_id
  from live_period lp
  order by lp.messages desc,lp.last_message_at desc
  limit greatest(1,least(coalesce(p_limit,10),100))
) x
where p_days is not null;
$function$;

create or replace function public.bot_chat_top_total(p_chat_id bigint, p_days integer default null)
returns integer
language sql
security definer
set search_path=public
as $function$
select case
  when p_days is null then
    coalesce((
      select s.source_total_messages
      from public.telegram_chat_import_state s
      where s.chat_id=p_chat_id
    ),0)
    + greatest(
        0,
        coalesce((select sum(a.message_count)::integer
                  from public.telegram_chat_activity a
                  where a.chat_id=p_chat_id),0)
        - coalesce((select s.baseline_live_messages
                    from public.telegram_chat_import_state s
                    where s.chat_id=p_chat_id),0)
      )
  else
    coalesce((
      select sum(a.message_count)::integer
      from public.telegram_chat_activity a
      where a.chat_id=p_chat_id
        and a.activity_date >= current_date-greatest(0,p_days-1)::integer
    ),0)
end;
$function$;

create or replace function public.bot_chat_stats(p_chat_id bigint)
returns json
language sql
security definer
set search_path=public
as $function$
select json_build_object(
  'total_messages', public.bot_chat_top_total(p_chat_id,null),
  'current_messages',
    greatest(
      0,
      coalesce((select sum(a.message_count)::integer
                from public.telegram_chat_activity a
                where a.chat_id=p_chat_id),0)
      - coalesce((select s.baseline_live_messages
                  from public.telegram_chat_import_state s
                  where s.chat_id=p_chat_id),0)
    ),
  'legacy_messages',
    coalesce((select count(*)::integer
              from public.iris_chat_stats_archive s
              where s.chat_id=p_chat_id and s.snapshot_kind='all_time'),0),
  'unique_users',
    (select count(*)::integer
     from public.iris_chat_stats_archive s
     where s.chat_id=p_chat_id and s.snapshot_kind='all_time'),
  'source',
    coalesce((select s.source from public.telegram_chat_import_state s where s.chat_id=p_chat_id),'PRISMA'),
  'source_total_messages',
    coalesce((select s.source_total_messages from public.telegram_chat_import_state s where s.chat_id=p_chat_id),0),
  'source_daily_messages',0
);
$function$;

-- Profile all-time activity: use the exact Iris snapshot for that person + post-transfer live delta.
create or replace function public.bot_get_chat_profile_stats(p_chat_id bigint,p_tg_id bigint)
returns json
language sql
security definer
set search_path=public
as $function$
select case
  when u.id is null then json_build_object('error','USER_NOT_FOUND')
  else json_build_object(
    'tg_id',u.telegram_id,
    'first_seen_at',coalesce(ps.first_seen_at,
      (select min(a.first_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),
      u.community_first_seen_at,u.created_at),
    'last_active_at',greatest(
      coalesce(ps.last_active_at,u.created_at),
      coalesce((select max(a.last_message_at) from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),u.created_at)
    ),
    'day_messages',
      case when ps.snapshot_at::date=current_date
           then coalesce(ps.day_messages,0)+greatest(0,coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0)-coalesce((select b.baseline_live_messages from public.telegram_chat_import_user_baseline b where b.chat_id=p_chat_id and b.user_id=u.id),0))
           else coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date=current_date),0)
      end,
    'week_messages',
      case when ps.snapshot_at is not null and date_trunc('week',ps.snapshot_at)=date_trunc('week',now())
           then coalesce(ps.week_messages,0)+greatest(0,coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0)-coalesce((select b.baseline_live_messages from public.telegram_chat_import_user_baseline b where b.chat_id=p_chat_id and b.user_id=u.id),0))
           else coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-6),0)
      end,
    'month_messages',
      case when ps.snapshot_at is not null and date_trunc('month',ps.snapshot_at)=date_trunc('month',now())
           then coalesce(ps.month_messages,0)+greatest(0,coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0)-coalesce((select b.baseline_live_messages from public.telegram_chat_import_user_baseline b where b.chat_id=p_chat_id and b.user_id=u.id),0))
           else coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id and a.activity_date>=current_date-29),0)
      end,
    'all_messages',
      coalesce((
        select s.message_count
        from public.iris_chat_stats_archive s
        where s.chat_id=p_chat_id and s.snapshot_kind='all_time'
          and (
            (s.telegram_id is not null and s.telegram_id=u.telegram_id)
            or
            (s.telegram_id is null and nullif(s.username,'') is not null
             and lower(s.username)=lower(coalesce(u.telegram_username,'')))
          )
        order by case when s.telegram_id is not null and s.telegram_id=u.telegram_id then 0 else 1 end,s.position
        limit 1
      ),
      coalesce((select sum(l.message_count)::integer from public.telegram_chat_activity_legacy l where l.chat_id=p_chat_id and l.user_id=u.id),0)
      )
      + greatest(
        0,
        coalesce((select sum(a.message_count)::integer from public.telegram_chat_activity a where a.chat_id=p_chat_id and a.user_id=u.id),0)
        - coalesce((select b.baseline_live_messages from public.telegram_chat_import_user_baseline b where b.chat_id=p_chat_id and b.user_id=u.id),0)
      ),
    'reputation_rating',coalesce(ps.reputation_rating,u.rating,0),
    'reputation_positive',coalesce(ps.reputation_positive,0),
    'activity_score',coalesce(ps.activity_score,u.activity_score,0)
  )
end
from public.users u
left join public.telegram_chat_profile_snapshot ps on ps.chat_id=p_chat_id and ps.user_id=u.id
where u.telegram_id=p_tg_id and u.deleted_at is null
limit 1;
$function$;

-- Normal PRISMA clan list: current clans + Iris-imported clans, in one list.
create or replace function public.bot_list_clans()
returns json
language sql
security definer
set search_path=public
as $function$
with active as (
  select c.id,c.name,c.tag,c.rating,c.level,c.xp,c.balance,c.wins,c.losses,c.description,c.type,c.status,c.created_at,c.source,c.source_number,
         owner.telegram_id owner_tg_id,
         coalesce(ia.leader_username,owner.telegram_username) owner_username,
         coalesce(ia.leader_name,owner.full_name) owner_full_name,
         greatest(
           (select count(*)::integer from public.clan_members cm where cm.clan_id=c.id and cm.status='active'),
           coalesce(ia.source_member_count,0)
         ) member_count,
         false is_imported_only
  from public.clans c
  join public.users owner on owner.id=c.owner_id
  left join public.iris_clan_import_archive ia on ia.source_number=c.source_number
  where c.deleted_at is null and c.status='active'
),
imported_only as (
  select null::uuid id,a.clan_name name,
         null::text tag,a.reputation rating,1 level,0::bigint xp,0::bigint balance,0 wins,0 losses,
         null::text description,a.clan_type type,'IMPORTED'::text status,
         a.founded_at::timestamptz created_at,'Iris'::text source,a.source_number,
         (select u.telegram_id from public.users u
          where lower(coalesce(u.telegram_username,''))=lower(coalesce(a.leader_username,''))
          order by u.is_whitelisted desc,u.created_at asc limit 1) owner_tg_id,
         a.leader_username owner_username,a.leader_name owner_full_name,
         coalesce(a.source_member_count,0)::integer member_count,
         true is_imported_only
  from public.iris_clan_import_archive a
  where not exists (
    select 1 from public.clans c
    where c.deleted_at is null and c.source='Iris' and c.source_number=a.source_number
  )
)
select coalesce(json_agg(x order by x.is_imported_only,x.source_number nulls last,x.rating desc,x.id),'[]'::json)
from (
  select * from active
  union all
  select * from imported_only
) x;
$function$;

-- Clan details: current PRISMA members are merged with original Iris members.
create or replace function public.bot_get_clan_by_position(p_position integer)
returns json
language sql
security definer
set search_path=public
as $function$
with ranked as (
  select c.*,row_number() over(order by c.rating desc,c.level desc,c.id)::integer position
  from public.clans c
  where c.deleted_at is null and c.status='active'
),
active_pick as (
  select r.* from ranked r
  where r.position=greatest(1,coalesce(p_position,1))
),
source_pick as (
  select c.*,
         p_position::integer position
  from public.clans c
  where false
),
picked as (
  select * from active_pick
  union all
  select
    null::uuid id,a.clan_name name,
    ('IR'||a.source_number)::text tag,
    null::uuid owner_id,
    null::text description,
    coalesce(a.reputation,0)::integer rating,
    a.founded_at::timestamptz created_at,
    now() updated_at,
    coalesce(a.clan_type,'open')::text type,
    'IMPORTED'::text status,
    1::integer level,0::bigint xp,0::bigint balance,0 wins,0 losses,
    null::text color,null::text avatar_url,null::timestamptz deleted_at,
    'Iris'::text source,a.source_number,
    p_position::integer position
  from public.iris_clan_import_archive a
  where a.source_number=p_position
    and not exists(select 1 from active_pick)
  limit 1
),
base_json as (
  select x.*,
         ia.leader_name ia_leader_name,ia.leader_username ia_leader_username,
         ia.source_member_count ia_member_count,ia.original_members
  from picked x
  left join public.iris_clan_import_archive ia on ia.source_number=x.source_number
)
select case
  when x.id is null and x.source_number is null then json_build_object('error','CLAN_NOT_FOUND')
  else json_build_object(
    'position',x.position,
    'id',x.id,
    'name',x.name,
    'tag',coalesce(x.tag,''),
    'type',x.type,
    'status',x.status,
    'owner_id',x.owner_id,
    'description',x.description,
    'rating',x.rating,
    'level',x.level,
    'xp',x.xp,
    'balance',x.balance,
    'wins',x.wins,
    'losses',x.losses,
    'created_at',x.created_at,
    'source',x.source,
    'source_number',x.source_number,
    'is_imported',x.status='IMPORTED',
    'leader',json_build_object(
      'tg_id',coalesce(
        (select u.telegram_id from public.users u
         where x.ia_leader_username is not null
           and lower(coalesce(u.telegram_username,''))=lower(x.ia_leader_username)
         order by u.is_whitelisted desc,u.created_at asc limit 1),
        owner.telegram_id
      ),
      'username',coalesce(x.ia_leader_username,owner.telegram_username),
      'full_name',coalesce(x.ia_leader_name,owner.full_name),
      'minecraft_nick',owner.minecraft_nickname
    ),
    'members',coalesce((
      with original as (
        select
          (select u.telegram_id from public.users u
           where nullif(m.value->>'username','') is not null
             and lower(coalesce(u.telegram_username,''))=lower(m.value->>'username')
           order by u.is_whitelisted desc,u.created_at asc limit 1) tg_id,
          nullif(m.value->>'username','') username,
          m.value->>'name' full_name,
          m.value->>'role' role,
          null::timestamptz joined_at,
          nullif(m.value->>'joined_text','') joined_text
        from jsonb_array_elements(coalesce(x.original_members,'[]'::jsonb)) m(value)
      ),
      current_members as (
        select u.telegram_id tg_id,u.telegram_username username,u.full_name,
               cm.role,cm.joined_at,null::text joined_text
        from public.clan_members cm
        join public.users u on u.id=cm.user_id
        where x.id is not null and cm.clan_id=x.id and cm.status='active'
      ),
      merged as (
        select * from original
        union all
        select cm.* from current_members cm
        where not exists (
          select 1 from original o
          where (o.tg_id is not null and o.tg_id=cm.tg_id)
             or (o.username is not null and lower(o.username)=lower(coalesce(cm.username,'')))
        )
      )
      select json_agg(json_build_object(
        'tg_id',m.tg_id,'username',m.username,'full_name',m.full_name,'role',m.role,
        'joined_at',m.joined_at,'joined_text',m.joined_text
      ) order by case when m.role='leader' or m.role='owner' then 0 else 1 end,m.joined_at nulls last,m.full_name)
      from merged m
    ),'[]'::json)
  )
end
from base_json x
left join public.users owner on owner.id=x.owner_id;
$function$;

-- All marriages in one normal PRISMA list; historical Iris records are not shown as a separate archive.
create or replace function public.bot_list_marriages()
returns json
language sql
security definer
set search_path=public
as $function$
with rows as (
  select ia.source_position,
         case when m.status='ACTIVE' then 'ACTIVE' else 'DIVORCED' end status,
         coalesce(ia.partner_a_tg_id,ua.telegram_id) user_a,
         coalesce(ia.partner_a_name,ua.full_name,ua.telegram_username) user_a_name,
         coalesce(ia.partner_a_username,ua.telegram_username) user_a_username,
         coalesce(ia.partner_b_tg_id,ub.telegram_id) user_b,
         coalesce(ia.partner_b_name,ub.full_name,ub.telegram_username) user_b_name,
         coalesce(ia.partner_b_username,ub.telegram_username) user_b_username,
         m.married_at,
         ia.duration_text,
         ia.green_wedding
  from public.marriages m
  join public.users ua on ua.id=m.user_a_id
  join public.users ub on ub.id=m.user_b_id
  left join public.iris_marriage_import_archive ia
    on ia.chat_id=-1003727618185 and ia.source_position=m.source_position
  where m.status='ACTIVE'

  union all

  select ia.source_position,'DIVORCED',
         ia.partner_a_tg_id,ia.partner_a_name,ia.partner_a_username,
         ia.partner_b_tg_id,ia.partner_b_name,ia.partner_b_username,
         null::timestamptz,null::text ia_duration,ia.green_wedding
  from public.iris_marriage_import_archive ia
  where ia.chat_id=-1003727618185
    and not exists (
      select 1 from public.marriages m
      where m.source_position=ia.source_position
    )
)
select coalesce(json_agg(r order by r.source_position),'[]'::json)
from rows r;
$function$;
