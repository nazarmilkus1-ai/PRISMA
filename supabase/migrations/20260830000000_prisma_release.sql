-- PRISMA RELEASE SQL
-- Safe to paste into Supabase SQL Editor. No DROP/WIPE operations.

create extension if not exists pgcrypto;

alter table public.moderation_logs
  alter column type type text using type::text;

alter table public.users
  add column if not exists phone_number text,
  add column if not exists minecraft_uuid uuid,
  add column if not exists rating integer not null default 0,
  add column if not exists activity_score integer not null default 0,
  add column if not exists last_seen_at timestamptz,
  add column if not exists is_banned boolean not null default false,
  add column if not exists ban_reason text,
  add column if not exists is_muted boolean not null default false,
  add column if not exists muted_until timestamptz;

create unique index if not exists users_minecraft_nick_lower_uidx
  on public.users (lower(trim(minecraft_nickname)))
  where minecraft_nickname is not null;
create unique index if not exists users_minecraft_uuid_uidx
  on public.users (mojang_uuid)
  where mojang_uuid is not null;
create index if not exists applications_pending_idx on public.applications(status, created_at desc);
create index if not exists applications_pending_created_idx on public.applications(status, created_at desc);
create index if not exists moderation_logs_pending_idx on public.moderation_logs(target_id, applied_at, created_at desc);
create index if not exists poll_ratings_poll_idx on public.poll_ratings(poll_id, user_id);

create table if not exists public.chat_settings (
  id boolean primary key default true check (id = true),
  main_chat_id bigint,
  admin_chat_id bigint,
  announcements_chat_id bigint,
  anti_profanity boolean not null default true,
  anti_caps boolean not null default true,
  anti_flood boolean not null default true,
  caps_threshold integer not null default 70 check (caps_threshold between 50 and 100),
  flood_messages integer not null default 5 check (flood_messages between 2 and 20),
  flood_window_seconds integer not null default 3 check (flood_window_seconds between 1 and 60),
  updated_at timestamptz not null default now()
);
insert into public.chat_settings(id) values(true) on conflict (id) do nothing;

create schema if not exists private;
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  description text,
  priority integer not null default 0
);
create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  key text unique not null,
  description text,
  category text
);
create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);
create table if not exists public.admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique not null references public.users(id) on delete cascade,
  role_id uuid references public.roles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 200),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  is_published boolean not null default false,
  published_at timestamptz,
  created_by uuid references public.admins(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists news_published_idx on public.news(is_published, published_at desc);

drop trigger if exists news_set_updated_at on public.news;
create trigger news_set_updated_at before update on public.news
for each row execute function public.set_updated_at();

create table if not exists public.settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  description text,
  updated_at timestamptz not null default now()
);
alter table public.polls
  add column if not exists description text,
  add column if not exists created_by uuid,
  add column if not exists chat_id bigint,
  add column if not exists status text not null default 'active',
  add column if not exists allow_multiple boolean not null default false,
  add column if not exists max_choices integer not null default 1,
  add column if not exists allow_add_options boolean not null default false,
  add column if not exists allow_change_vote boolean not null default true,
  add column if not exists show_voters boolean not null default false,
  add column if not exists shuffle_options boolean not null default false,
  add column if not exists has_correct_answer boolean not null default false,
  add column if not exists expires_at timestamptz,
  add column if not exists finished_at timestamptz;
create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  text text not null,
  position integer not null,
  is_correct boolean not null default false
);
create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (poll_id, option_id, user_id)
);
alter table public.clans
  add column if not exists type text not null default 'open',
  add column if not exists status text not null default 'active';
create table if not exists public.clan_members (
  clan_id uuid not null references public.clans(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (clan_id, user_id),
  unique (user_id)
);
create or replace function private.has_permission(p_permission_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select false;
$$;

-- Poll vote duplicate protection for the canonical poll schema.
create unique index if not exists poll_ratings_unique_choice_uidx
  on public.poll_ratings(poll_id, user_id);

-- Normalize permission data expected by the release.
insert into public.roles(name, description, priority)
select * from (values
  ('owner','Повний доступ',100),
  ('head_admin','Главный администратор',80),
  ('admin','Администратор',60),
  ('moderator','Модератор',40),
  ('content_maker','Контент-мейкер',20)
) v(name,description,priority)
where not exists (select 1 from public.roles r where r.name=v.name);

insert into public.permissions(key,description,category)
select * from (values
 ('application.view','Перегляд анкет','applications'),
 ('application.approve','Схвалення анкет','applications'),
 ('application.reject','Отклонение заявок','applications'),
 ('punishment.warn','Видача попереджень','moderation'),
 ('punishment.mute','Выдача мутов','moderation'),
 ('punishment.ban','Выдача банов','moderation'),
 ('punishment.kick','Выдача киков','moderation'),
 ('punishment.remove','Зняття покарань','moderation'),
 ('punishment.view_history','Просмотр истории наказаний','moderation'),
 ('report.view','Перегляд скарг','reports'),
 ('report.assign','Призначення скарг','reports'),
 ('report.resolve','Решение жалоб','reports'),
 ('report.reject','Отклонение жалоб','reports'),
 ('poll.create','Створення опитувань','polls'),
 ('poll.finish','Завершення опитувань','polls'),
 ('poll.manage','Керування опитуваннями','polls'),
 ('clan.manage','Керування кланами','clans'),
 ('clan.view_all','Просмотр всех кланов','clans'),
 ('settings.view','Перегляд налаштувань','settings'),
 ('settings.manage','Керування налаштуваннями','settings'),
 ('admin.manage','Управление администраторами','admin'),
 ('admin.view_audit','Перегляд аудиту','admin')
) v(key,description,category)
where not exists (select 1 from public.permissions p where p.key=v.key);

-- Role grants: owner all, head_admin all except admin.manage, admin operational, moderator moderation/report view, content_maker view only.
insert into public.role_permissions(role_id, permission_id)
select r.id,p.id
from public.roles r cross join public.permissions p
where r.name='owner'
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id,p.id
from public.roles r join public.permissions p on p.key in (
  'application.view','application.approve','application.reject','punishment.warn','punishment.mute','punishment.ban','punishment.kick',
  'punishment.remove','punishment.view_history','report.view','report.assign','report.resolve','report.reject',
  'poll.create','poll.finish','poll.manage','clan.manage','clan.view_all','settings.view','settings.manage','admin.view_audit'
)
where r.name='head_admin'
on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p
on p.key in ('application.view','application.approve','application.reject','punishment.warn','punishment.mute','punishment.ban','punishment.kick','punishment.remove','punishment.view_history','report.view','report.assign','report.resolve','report.reject','poll.create','poll.finish','poll.manage','clan.manage','clan.view_all','settings.view','settings.manage')
where r.name='admin' on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p
on p.key in ('application.view','punishment.warn','punishment.mute','punishment.ban','punishment.kick','punishment.remove','punishment.view_history','report.view')
where r.name='moderator' on conflict do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.key in ('application.view','report.view')
where r.name='content_maker' on conflict do nothing;

create or replace function private.get_user_by_tg_id(p_tg_id bigint)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.users where telegram_id=p_tg_id limit 1;
$$;

create or replace function private.get_admin_by_tg_id(p_tg_id bigint)
returns uuid language sql stable security definer set search_path = '' as $$
  select a.id from public.admins a join public.users u on u.id=a.user_id where u.telegram_id=p_tg_id limit 1;
$$;

create or replace function public.bot_ensure_owner(p_tg_id bigint)
returns json language plpgsql security definer set search_path = '' as $$
declare uid uuid; aid uuid; rid uuid;
begin
  if p_tg_id is null or p_tg_id=0 then return json_build_object('success',false,'error','OWNER_TG_ID_NOT_SET'); end if;
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then insert into public.users(telegram_id,is_whitelisted) values(p_tg_id,false) returning id into uid; end if;
  select id into aid from public.admins where user_id=uid;
  select id into rid from public.roles where name='owner' limit 1;
  if aid is null and rid is not null then
    insert into public.admins(user_id,role_id) values(uid,rid) returning id into aid;
  end if;
  return json_build_object('success',true,'user_id',uid,'admin_id',aid);
end;$$;

create or replace function public.create_user_with_application(
  p_tg_id bigint,p_username text,p_full_name text,p_birth_date date,p_minecraft_nick text,p_platform text,p_goal text,p_about text
) returns json language plpgsql security definer set search_path = 'public' as $$
begin
  return public.bot_submit_application(p_tg_id,p_username,p_full_name,p_birth_date,p_minecraft_nick,p_platform,p_goal,p_about,null);
end;$$;

create or replace function public.bot_submit_application(
  p_tg_id bigint,p_username text,p_full_name text,p_birth_date date,p_minecraft_nick text,p_platform text,p_goal text,p_about text,p_phone_number text default null
) returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; appid uuid; last_status text; v_age integer;
begin
  if p_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if p_birth_date is null or p_birth_date > current_date then raise exception 'INVALID_BIRTH_DATE'; end if;
  v_age := extract(year from age(current_date,p_birth_date));
  if v_age < 14 then raise exception 'AGE_TOO_YOUNG'; end if;
  if p_minecraft_nick is null or p_minecraft_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;
  if p_platform not in ('Java','Bedrock') then raise exception 'INVALID_PLATFORM'; end if;
  if exists(select 1 from public.users u where u.telegram_id<>p_tg_id and lower(trim(u.minecraft_nickname))=lower(trim(p_minecraft_nick))) then raise exception 'MINECRAFT_NICK_TAKEN'; end if;
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then
    insert into public.users(telegram_id,telegram_username,full_name,age,minecraft_nickname,platform,is_whitelisted) values(p_tg_id,p_username,p_full_name,v_age,trim(p_minecraft_nick),upper(p_platform)::public.platform_type,false) returning id into uid;
  else
    update public.users set telegram_username=p_username,full_name=p_full_name,age=v_age,minecraft_nickname=trim(p_minecraft_nick),platform=upper(p_platform)::public.platform_type,updated_at=now() where id=uid;
  end if;
  select status into last_status from public.applications where user_id=uid order by created_at desc,id desc limit 1;
  if last_status='PENDING' then raise exception 'APPLICATION_PENDING'; end if;
  if last_status='ACCEPTED' then raise exception 'APPLICATION_ALREADY_ACTIVE'; end if;
  insert into public.applications(user_id,full_name,age,nickname,platform,discovery_source,status) values(uid,p_full_name,v_age,trim(p_minecraft_nick),upper(p_platform)::public.platform_type,'Telegram','PENDING') returning id into appid;
  return json_build_object('success',true,'user_id',uid,'application_id',appid);
end;$$;

create or replace function public.get_user_profile(p_tg_id bigint)
returns json language plpgsql security definer set search_path='public' as $$
declare profile record; warns integer;
begin
  select usr.*, app.status as application_status into profile
  from public.users usr
  left join lateral (
    select applications.status
    from public.applications
    where applications.user_id=usr.id
    order by applications.created_at desc, applications.id desc
    limit 1
  ) app on true
  where usr.telegram_id=p_tg_id;
  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;
  select count(*) into warns from public.moderation_logs where target_id=profile.id and type='WARN';
  return json_build_object('id',profile.id,'tg_id',profile.telegram_id,'username',profile.telegram_username,'full_name',profile.full_name,'minecraft_nick',profile.minecraft_nickname,'platform',profile.platform,'is_whitelisted',profile.is_whitelisted,'application_status',profile.application_status,'rating',profile.rating,'activity_score',profile.activity_score,'active_warns',warns,'is_banned',profile.is_banned,'is_muted',profile.is_muted,'muted_until',profile.muted_until);
end;$$;

create or replace function public.bot_get_profile(p_tg_id bigint) returns json language sql security definer set search_path='public' as $$ select public.get_user_profile(p_tg_id); $$;

create or replace function public.bot_check_admin_permission(p_tg_id bigint,p_permission_key text)
returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.admins a join public.users u on u.id=a.user_id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where u.telegram_id=p_tg_id and p.key=p_permission_key);
$$;

create or replace function public.has_permission_external(p_permission_key text) returns boolean language sql stable security definer set search_path='' as $$ select private.has_permission(p_permission_key); $$;

create or replace function public.bot_change_minecraft_nick(p_tg_id bigint,p_new_nick text)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; was_whitelisted boolean;
begin
  if p_new_nick is null or p_new_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;
  select id,is_whitelisted into uid,was_whitelisted from public.users where telegram_id=p_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if exists(select 1 from public.users where id<>uid and lower(trim(minecraft_nickname))=lower(trim(p_new_nick))) then raise exception 'MINECRAFT_NICK_TAKEN'; end if;
  update public.users set minecraft_nickname=trim(p_new_nick),updated_at=now() where id=uid;
  return json_build_object('success',true,'minecraft_nick',trim(p_new_nick),'whitelist_sync',was_whitelisted);
end;$$;

create or replace function public.bot_find_user(p_identifier text)
returns json language plpgsql security definer set search_path='public' as $$
declare u record; ident text;
begin
  ident:=trim(p_identifier);
  select * into u from public.users where telegram_id=case when ident ~ '^\\d+$' then ident::bigint else null end limit 1;
  if not found then select * into u from public.users where lower(coalesce(telegram_username,''))=lower(ltrim(ident,'@')) limit 1; end if;
  if not found then select * into u from public.users where lower(coalesce(minecraft_nickname,''))=lower(ident) limit 1; end if;
  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;
  return json_build_object('id',u.id,'tg_id',u.telegram_id,'username',u.telegram_username,'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname,'is_whitelisted',u.is_whitelisted);
end;$$;

create or replace function public.bot_create_report(p_reporter_tg_id bigint,p_target_tg_id bigint,p_reason text)
returns json language plpgsql security definer set search_path='public' as $$
declare reporter uuid; target uuid; rid uuid;
begin
  select id into reporter from public.users where telegram_id=p_reporter_tg_id;
  select id into target from public.users where telegram_id=p_target_tg_id;
  if reporter is null or target is null then raise exception 'USER_NOT_FOUND'; end if;
  if reporter=target then raise exception 'CANNOT_REPORT_SELF'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 3 and 4000 then raise exception 'INVALID_REASON'; end if;
  insert into public.reports(user_id,type,target_nickname,description,status)
  values(reporter,'PLAYER', (select minecraft_nickname from public.users where id=target), trim(p_reason),'OPEN') returning id into rid;
  return json_build_object('success',true,'report_id',rid);
end;$$;

create or replace function public.bot_create_punishment(p_user_tg_id bigint,p_type text,p_reason text,p_admin_tg_id bigint,p_duration integer default null,p_source_type text default 'manual',p_source_id uuid default null)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; aid uuid; perm text; pid uuid; expires timestamptz; cmd jsonb;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id;
  select id into aid from public.admins a join public.users u on u.id=a.user_id where u.telegram_id=p_admin_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if aid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  perm:=case lower(p_type) when 'warn' then 'punishment.warn' when 'mute' then 'punishment.mute' when 'ban' then 'punishment.ban' when 'kick' then 'punishment.kick' else null end;
  if perm is null then raise exception 'UNKNOWN_PUNISHMENT_TYPE'; end if;
  if not exists(select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id join public.admins a on a.role_id=rp.role_id where a.id=aid and p.key=perm) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
  if p_reason is null or char_length(trim(p_reason)) not between 1 and 2000 then raise exception 'INVALID_REASON'; end if;
  if p_duration is not null and p_duration<=0 then raise exception 'INVALID_DURATION'; end if;
  expires:=case when p_duration is not null then now()+make_interval(secs=>p_duration) else null end;
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,duration_minutes,expires_at,source)
  values(uid,p_admin_tg_id,null,upper(p_type),trim(p_reason),p_duration,expires,'BOT') returning id into pid;
  if lower(p_type)='mute' then update public.users set is_muted=true,muted_until=expires where id=uid; end if;
  if lower(p_type)='ban' then update public.users set is_banned=true,ban_reason=trim(p_reason),is_whitelisted=false where id=uid; end if;
  cmd:=jsonb_build_object('punishment_id',pid,'user_id',uid,'type',upper(p_type),'reason',trim(p_reason),'duration',p_duration,'minecraft_nick',(select minecraft_nickname from public.users where id=uid));
  return json_build_object('success',true,'punishment_id',pid,'expires_at',expires);
end;$$;

create or replace function public.bot_lift_punishment(p_user_tg_id bigint,p_type text,p_admin_tg_id bigint)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; aid uuid; pid uuid; typ text; cmd jsonb;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id;
  select a.id into aid from public.admins a join public.users u on u.id=a.user_id where u.telegram_id=p_admin_tg_id;
  if uid is null or aid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if p_type not in ('warn','mute') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;
  select id into pid from public.moderation_logs where target_id=uid and type=upper(p_type) order by created_at desc limit 1;
  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;
  if p_type='mute' then update public.users set is_muted=false,muted_until=null where id=uid; end if;
  insert into public.moderation_logs(target_id,issued_by_tg_id,issued_by_name,type,reason,source)
  values(uid,p_admin_tg_id,null,case when p_type='mute' then 'UNMUTE' else 'UNWARN' end, 'Покарання знято','BOT') returning id into pid;
  return json_build_object('success',true,'punishment_id',pid);
end;$$;

create or replace function public.bot_get_punishment_history(p_user_tg_id bigint,p_admin_tg_id bigint)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; aid uuid; out json;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id; select id into aid from public.admins a join public.users u on u.id=a.user_id where u.telegram_id=p_admin_tg_id;
  if uid is null or aid is null or not public.bot_check_admin_permission(p_admin_tg_id,'punishment.view_history') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
  select coalesce(json_agg(json_build_object('id',p.id,'type',p.type,'reason',p.reason,'duration',p.duration_minutes,'expires_at',p.expires_at,'issued_at',p.created_at) order by p.created_at desc),'[]'::json) into out from public.moderation_logs p where p.target_id=uid;
  return out;
end;$$;

create or replace function public.bot_get_active_punishments_for_plugin()
returns json language sql security definer set search_path='public' as $$
select coalesce(json_agg(json_build_object('id',p.id,'type',p.type,'reason',p.reason,'duration',p.duration_minutes,'expires_at',p.expires_at,'minecraft_nick',u.minecraft_nickname) order by p.created_at),'[]'::json) from public.moderation_logs p join public.users u on u.id=p.target_id where p.applied_at is null and p.type in ('MUTE','BAN');
$$;

create or replace function public.bot_get_clan_info(p_tg_id bigint)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; cid uuid; out json;
begin
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;
  select clan_id into cid from public.clan_members where user_id=uid limit 1;
  if cid is null then return json_build_object('error','NO_CLAN'); end if;
  select json_build_object('id',c.id,'name',c.name,'type',c.type,'status',c.status,'owner_id',c.owner_id,'members',coalesce((select json_agg(json_build_object('user_id',u.id,'tg_id',u.telegram_id,'full_name',u.full_name,'minecraft_nick',u.minecraft_nickname,'role',cm.role) order by cm.joined_at) from public.clan_members cm join public.users u on u.id=cm.user_id where cm.clan_id=c.id),'[]'::json)) into out from public.clans c where c.id=cid;
  return out;
end;$$;

create or replace function public.bot_create_clan(p_tg_id bigint,p_name text)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; cid uuid;
begin
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if exists(select 1 from public.clan_members where user_id=uid) then raise exception 'USER_ALREADY_IN_CLAN'; end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 32 then raise exception 'INVALID_CLAN_NAME'; end if;
  if exists(select 1 from public.clans where lower(name)=lower(trim(p_name))) then raise exception 'CLAN_NAME_TAKEN'; end if;
  insert into public.clans(name,owner_id,type,status) values(trim(p_name),uid,'open','active') returning id into cid;
  insert into public.clan_members(clan_id,user_id,role) values(cid,uid,'owner');
  return json_build_object('success',true,'clan_id',cid,'name',trim(p_name));
end;$$;

create or replace function public.bot_create_poll(p_tg_id bigint,p_question text,p_description text,p_options text[],p_chat_id bigint,p_allow_multiple boolean default false,p_max_choices integer default 1,p_allow_add_options boolean default false,p_allow_change_vote boolean default true,p_show_voters boolean default false,p_expires_at timestamptz default null,p_has_correct_answer boolean default false,p_correct_options integer[] default '{}')
returns json language plpgsql security definer set search_path='public' as $$
declare aid uuid; pid uuid; i int;
begin
  select private.get_admin_by_tg_id(p_tg_id) into aid;
  if aid is null or not public.bot_check_admin_permission(p_tg_id,'poll.create') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
  if p_question is null or char_length(trim(p_question)) not between 3 and 1000 then raise exception 'INVALID_QUESTION'; end if;
  if coalesce(array_length(p_options,1),0) not between 2 and 11 then raise exception 'INVALID_OPTIONS'; end if;
  if p_allow_multiple and (p_max_choices is null or p_max_choices<1 or p_max_choices>array_length(p_options,1)) then raise exception 'INVALID_MAX_CHOICES'; end if;
  insert into public.polls(question,description,created_by,chat_id,status,allow_multiple,max_choices,allow_add_options,allow_change_vote,show_voters,shuffle_options,has_correct_answer,expires_at)
  values(trim(p_question),nullif(trim(p_description),''),aid,p_chat_id,'active',p_allow_multiple,case when p_allow_multiple then p_max_choices else 1 end,p_allow_add_options,p_allow_change_vote,p_show_voters,false,p_has_correct_answer,p_expires_at) returning id into pid;
  for i in 1..array_length(p_options,1) loop insert into public.poll_options(poll_id,text,position,is_correct) values(pid,trim(p_options[i]),i,p_has_correct_answer and i=any(p_correct_options)); end loop;
  return json_build_object('success',true,'poll_id',pid);
end;$$;

create or replace function public.bot_vote_poll(p_poll_id uuid,p_option_id uuid,p_tg_id bigint)
returns json language plpgsql security definer set search_path='public' as $$
declare uid uuid; p record; existing int;
begin
  select id into uid from public.users where telegram_id=p_tg_id;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  select * into p from public.polls where id=p_poll_id for update;
  if not found or p.status<>'active' then raise exception 'POLL_NOT_ACTIVE'; end if;
  if p.expires_at is not null and p.expires_at<=now() then update public.polls set status='finished',finished_at=now() where id=p.id; raise exception 'POLL_EXPIRED'; end if;
  if not exists(select 1 from public.poll_options where id=p_option_id and poll_id=p_poll_id) then raise exception 'INVALID_OPTION'; end if;
  select count(*) into existing from public.poll_votes where poll_id=p_poll_id and user_id=uid;
  if not p.allow_multiple and existing>0 then
    if not p.allow_change_vote then raise exception 'CANNOT_CHANGE_VOTE'; end if;
    delete from public.poll_votes where poll_id=p_poll_id and user_id=uid;
  elsif p.allow_multiple and existing>=coalesce(p.max_choices,1) then raise exception 'MAX_CHOICES_REACHED'; end if;
  insert into public.poll_votes(poll_id,option_id,user_id) values(p_poll_id,p_option_id,uid);
  return json_build_object('success',true);
end;$$;

create or replace function public.bot_get_polls(p_tg_id bigint) returns json language sql security definer set search_path='public' as $$
select coalesce(json_agg(x),'[]'::json) from (select p.id,p.question,p.description,p.status,p.expires_at,json_agg(json_build_object('id',o.id,'text',o.text,'position',o.position,'is_correct',o.is_correct) order by o.position) options from public.polls p join public.poll_options o on o.poll_id=p.id where p.status='active' group by p.id order by p.created_at desc limit 20) x;
$$;

create or replace function public.bot_get_poll(p_poll_id uuid,p_tg_id bigint) returns json language sql security definer set search_path='public' as $$
select json_build_object('id',p.id,'question',p.question,'description',p.description,'status',p.status,'expires_at',p.expires_at,'options',(select coalesce(json_agg(json_build_object('id',o.id,'text',o.text,'position',o.position) order by o.position),'[]'::json) from public.poll_options o where o.poll_id=p.id))
from public.polls p
where p.id=p_poll_id;
$$;

create or replace function public.bot_get_poll_for_message(p_poll_id uuid) returns json language sql security definer set search_path='public' as $$ select public.bot_get_poll(p_poll_id,null); $$;

create or replace function public.bot_finish_poll(p_poll_id uuid,p_tg_id bigint) returns json language plpgsql security definer set search_path='public' as $$ begin if not public.bot_check_admin_permission(p_tg_id,'poll.finish') then raise exception 'ADMIN_LACKS_PERMISSION'; end if; update public.polls set status='finished',finished_at=now() where id=p_poll_id and status='active'; return json_build_object('success',true,'poll_id',p_poll_id); end; $$;
create or replace function public.bot_add_poll_option(p_poll_id uuid,p_text text,p_tg_id bigint) returns json language plpgsql security definer set search_path='public' as $$ declare pos int; begin if not public.bot_check_admin_permission(p_tg_id,'poll.manage') then raise exception 'ADMIN_LACKS_PERMISSION'; end if; if p_text is null or char_length(trim(p_text))<1 then raise exception 'INVALID_OPTION'; end if; select coalesce(max(position),0)+1 into pos from public.poll_options where poll_id=p_poll_id; if pos>11 then raise exception 'MAX_OPTIONS'; end if; insert into public.poll_options(poll_id,text,position,is_correct) values(p_poll_id,trim(p_text),pos,false); return json_build_object('success',true); end; $$;
create or replace function public.bot_get_pending_count() returns integer language sql security definer set search_path='public' as $$ select count(*)::int from public.applications where status='PENDING'; $$;

-- Harden function execute privileges: only the server-side service role should call the privileged RPC surface.
grant usage on schema public to service_role;
grant execute on function public.bot_submit_application(bigint,text,text,date,text,text,text,text,text) to service_role;
grant execute on function public.create_user_with_application(bigint,text,text,date,text,text,text,text) to service_role;
grant execute on function public.bot_check_admin_permission(bigint,text) to service_role;
grant execute on function public.bot_change_minecraft_nick(bigint,text) to service_role;
grant execute on function public.bot_create_report(bigint,bigint,text) to service_role;
grant execute on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) to service_role;
grant execute on function public.bot_lift_punishment(bigint,text,bigint) to service_role;
grant execute on function public.bot_get_punishment_history(bigint,bigint) to service_role;
grant execute on function public.bot_get_profile(bigint) to service_role;
grant execute on function public.bot_get_clan_info(bigint) to service_role;
grant execute on function public.bot_create_clan(bigint,text) to service_role;
grant execute on function public.bot_create_poll(bigint,text,text,text[],bigint,boolean,integer,boolean,boolean,boolean,timestamptz,boolean,integer[]) to service_role;
grant execute on function public.bot_vote_poll(uuid,uuid,bigint) to service_role;
grant execute on function public.bot_get_polls(bigint) to service_role;
grant execute on function public.bot_get_poll(uuid,bigint) to service_role;
grant execute on function public.bot_get_poll_for_message(uuid) to service_role;
grant execute on function public.bot_add_poll_option(uuid,text,bigint) to service_role;
grant execute on function public.bot_finish_poll(uuid,bigint) to service_role;
grant execute on function public.bot_get_pending_count() to service_role;
grant execute on function public.bot_ensure_owner(bigint) to service_role;

revoke all on function public.bot_submit_application(bigint,text,text,date,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.create_user_with_application(bigint,text,text,date,text,text,text,text) from public,anon,authenticated;
revoke all on function public.bot_check_admin_permission(bigint,text) from public,anon,authenticated;
revoke all on function public.bot_change_minecraft_nick(bigint,text) from public,anon,authenticated;
revoke all on function public.bot_create_report(bigint,bigint,text) from public,anon,authenticated;
revoke all on function public.bot_create_punishment(bigint,text,text,bigint,integer,text,uuid) from public,anon,authenticated;
revoke all on function public.bot_lift_punishment(bigint,text,bigint) from public,anon,authenticated;
revoke all on function public.bot_get_punishment_history(bigint,bigint) from public,anon,authenticated;
revoke all on function public.bot_get_profile(bigint) from public,anon,authenticated;
revoke all on function public.bot_get_clan_info(bigint) from public,anon,authenticated;
revoke all on function public.bot_create_clan(bigint,text) from public,anon,authenticated;
revoke all on function public.bot_create_poll(bigint,text,text,text[],bigint,boolean,integer,boolean,boolean,boolean,timestamptz,boolean,integer[]) from public,anon,authenticated;
revoke all on function public.bot_vote_poll(uuid,uuid,bigint) from public,anon,authenticated;
revoke all on function public.bot_get_polls(bigint) from public,anon,authenticated;
revoke all on function public.bot_get_poll(uuid,bigint) from public,anon,authenticated;
revoke all on function public.bot_finish_poll(uuid,bigint) from public,anon,authenticated;
revoke all on function public.bot_get_pending_count() from public,anon,authenticated;

-- Verify/recover the existing approval function permission model by leaving its SECURITY DEFINER body intact.

insert into public.settings(key,value,description) values
('telegram_groups',jsonb_build_object('main',null,'admin',null,'announcements',null),'Telegram group IDs'),
('moderation_rules',jsonb_build_object('anti_profanity',true,'anti_caps',true,'anti_flood',true,'caps_threshold',70,'flood_messages',5,'flood_window_seconds',3),'Chat moderation'),
('punishment_presets',jsonb_build_object(),'Moderation presets'),
('archive_days',jsonb_build_object('days',30),'Days before application archive')
on conflict (key) do nothing;

select 'PRISMA_RELEASE_OK' as status;
