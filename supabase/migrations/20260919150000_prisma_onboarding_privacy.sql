-- PRISMA onboarding/privacy hardening:
-- 1) remove phone data completely
-- 2) track community members seen by the bot without requiring a DM
-- 3) add one-time Telegram <-> Minecraft binding codes

drop function if exists public.bot_submit_application(bigint,text,text,date,text,text,text,text,text);

alter table public.users
  add column if not exists community_first_seen_at timestamptz,
  add column if not exists community_last_seen_at timestamptz,
  add column if not exists bot_started_at timestamptz;

alter table public.users
  drop column if exists phone_number;

alter table public.applications
  drop column if exists phone_number;

create table if not exists public.minecraft_link_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists minecraft_link_codes_user_idx
  on public.minecraft_link_codes(user_id, created_at desc);

create index if not exists minecraft_link_codes_expiry_idx
  on public.minecraft_link_codes(expires_at)
  where used_at is null;

alter table public.minecraft_link_codes enable row level security;
revoke all on public.minecraft_link_codes from public, anon, authenticated;
grant all on public.minecraft_link_codes to service_role;

create or replace function public.bot_touch_user(
  p_tg_id bigint,
  p_username text default null,
  p_first_name text default null,
  p_last_name text default null,
  p_full_name text default null,
  p_context text default 'GROUP'
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  uid uuid;
  now_ts timestamptz := now();
  ctx text := upper(coalesce(p_context,'GROUP'));
begin
  if p_tg_id is null then
    raise exception 'INVALID_TELEGRAM_ID';
  end if;

  select id into uid
  from public.users
  where telegram_id=p_tg_id
  for update;

  if uid is null then
    insert into public.users(
      telegram_id, telegram_username, first_name, last_name, full_name,
      status, is_whitelisted, community_first_seen_at, community_last_seen_at,
      bot_started_at
    ) values (
      p_tg_id, nullif(trim(p_username),''), nullif(trim(p_first_name),''),
      nullif(trim(p_last_name),''), nullif(trim(p_full_name),''),
      'PENDING', false,
      case when ctx='GROUP' then now_ts else null end,
      case when ctx='GROUP' then now_ts else null end,
      case when ctx='PRIVATE' then now_ts else null end
    )
    returning id into uid;
  else
    update public.users
    set telegram_username=coalesce(nullif(trim(p_username),''), telegram_username),
        first_name=coalesce(nullif(trim(p_first_name),''), first_name),
        last_name=coalesce(nullif(trim(p_last_name),''), last_name),
        full_name=coalesce(nullif(trim(p_full_name),''), full_name),
        community_first_seen_at=case
          when ctx='GROUP' then coalesce(community_first_seen_at, now_ts)
          else community_first_seen_at
        end,
        community_last_seen_at=case
          when ctx='GROUP' then now_ts
          else community_last_seen_at
        end,
        bot_started_at=case
          when ctx='PRIVATE' then coalesce(bot_started_at, now_ts)
          else bot_started_at
        end,
        updated_at=now_ts
    where id=uid;
  end if;

  return json_build_object('success',true,'user_id',uid);
end;
$$;

create or replace function public.bot_submit_application(
  p_tg_id bigint,
  p_username text,
  p_full_name text,
  p_birth_date date,
  p_minecraft_nick text,
  p_platform text,
  p_goal text,
  p_about text
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  uid uuid;
  appid uuid;
  age_years integer;
  last_status public.application_status;
  v_raw_nick text;
  v_nick text;
  v_platform text;
begin
  if p_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if p_birth_date is null or p_birth_date > current_date then raise exception 'INVALID_BIRTH_DATE'; end if;

  age_years := extract(year from age(current_date,p_birth_date))::integer;
  if age_years < 14 then raise exception 'AGE_TOO_YOUNG'; end if;

  v_raw_nick := trim(p_minecraft_nick);
  if v_raw_nick is null or v_raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then
    raise exception 'INVALID_MINECRAFT_NICK';
  end if;

  v_platform := upper(trim(p_platform));
  if v_platform not in ('JAVA','BEDROCK') then raise exception 'INVALID_PLATFORM'; end if;

  v_nick := case when v_platform='BEDROCK' then '.' || v_raw_nick else v_raw_nick end;

  if exists (
    select 1
    from public.users u
    where u.telegram_id <> p_tg_id
      and lower(trim(u.minecraft_nickname))=lower(v_nick)
  ) then
    raise exception 'MINECRAFT_NICK_TAKEN';
  end if;

  select id into uid
  from public.users
  where telegram_id=p_tg_id;

  if uid is null then
    insert into public.users(
      telegram_id, telegram_username, full_name, age,
      minecraft_nickname, platform, is_whitelisted, status
    ) values (
      p_tg_id, p_username, p_full_name, age_years,
      v_nick, v_platform::public.platform_type, false, 'PENDING'
    )
    returning id into uid;
  else
    select status into last_status
    from public.applications
    where user_id=uid
    order by created_at desc,id desc
    limit 1;

    if last_status='PENDING' then raise exception 'APPLICATION_PENDING'; end if;
    if last_status='ACCEPTED' then raise exception 'APPLICATION_ALREADY_ACTIVE'; end if;

    update public.users
    set telegram_username=p_username,
        full_name=p_full_name,
        age=age_years,
        birth_date=p_birth_date,
        minecraft_nickname=v_nick,
        platform=v_platform::public.platform_type,
        status='PENDING',
        updated_at=now()
    where id=uid;
  end if;

  insert into public.applications(
    user_id, full_name, age, nickname, platform,
    discovery_source, status, birth_date, goal, about
  ) values (
    uid, p_full_name, age_years, v_raw_nick,
    v_platform::public.platform_type, 'Telegram', 'PENDING',
    p_birth_date, nullif(trim(p_goal),''), nullif(trim(p_about),'')
  )
  returning id into appid;

  insert into public.application_history(application_id,action,actor_tg_id)
  values(appid,'CREATED',p_tg_id);

  return json_build_object(
    'success',true,
    'user_id',uid,
    'application_id',appid,
    'minecraft_nick',v_nick
  );
end;
$$;

create or replace function public.get_user_profile(p_tg_id bigint)
returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  profile record;
  warns integer;
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

  if not found then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  select count(*) into warns
  from public.moderation_logs
  where target_id=profile.id and type='WARN' and revoked=false;

  return json_build_object(
    'id',profile.id,
    'tg_id',profile.telegram_id,
    'username',profile.telegram_username,
    'full_name',profile.full_name,
    'birth_date',profile.birth_date,
    'minecraft_nick',profile.minecraft_nickname,
    'minecraft_uuid',profile.minecraft_uuid,
    'mojang_uuid',profile.mojang_uuid,
    'platform',profile.platform,
    'is_whitelisted',profile.is_whitelisted,
    'application_status',profile.application_status,
    'rating',profile.rating,
    'activity_score',profile.activity_score,
    'level',profile.level,
    'xp',profile.xp,
    'last_seen_at',profile.last_seen_at,
    'active_warns',warns,
    'is_banned',profile.is_banned,
    'banned_until',profile.banned_until,
    'is_muted',profile.is_muted,
    'muted_until',profile.muted_until,
    'clan_id',profile.clan_id
  );
end;
$$;

create or replace function public.bot_create_minecraft_link_code(
  p_tg_id bigint,
  p_code_hash text
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  uid uuid;
  expires timestamptz := now() + interval '10 minutes';
begin
  if p_tg_id is null or p_code_hash is null or char_length(p_code_hash) <> 64 then
    raise exception 'INVALID_LINK_CODE';
  end if;

  select id into uid
  from public.users
  where telegram_id=p_tg_id
    and status='ACCEPTED'
    and is_whitelisted=true
    and deleted_at is null;

  if uid is null then raise exception 'USER_NOT_ELIGIBLE'; end if;

  if exists(select 1 from public.users where id=uid and mojang_uuid is not null) then
    raise exception 'ALREADY_LINKED';
  end if;

  delete from public.minecraft_link_codes
  where user_id=uid and used_at is null;

  insert into public.minecraft_link_codes(user_id,code_hash,expires_at)
  values(uid,lower(p_code_hash),expires);

  return json_build_object(
    'success',true,
    'expires_at',expires
  );
end;
$$;

create or replace function public.bot_consume_minecraft_link_code(
  p_code_hash text,
  p_minecraft_uuid text
) returns json
language plpgsql
security definer
set search_path='public'
as $$
declare
  code_row record;
  current_binding text;
begin
  if p_code_hash is null or char_length(p_code_hash) <> 64 then
    raise exception 'INVALID_LINK_CODE';
  end if;

  if p_minecraft_uuid is null or p_minecraft_uuid !~ '^[0-9a-fA-F-]{36}$' then
    raise exception 'INVALID_MINECRAFT_UUID';
  end if;

  select c.id, c.user_id, c.expires_at
    into code_row
  from public.minecraft_link_codes c
  where c.code_hash=lower(p_code_hash)
    and c.used_at is null
    and c.expires_at>now()
  for update;

  if code_row.id is null then
    raise exception 'LINK_CODE_INVALID_OR_EXPIRED';
  end if;

  select mojang_uuid into current_binding
  from public.users
  where id=code_row.user_id
  for update;

  if current_binding is not null then
    update public.minecraft_link_codes
    set used_at=now()
    where id=code_row.id;
    raise exception 'ALREADY_LINKED';
  end if;

  update public.users
  set mojang_uuid=lower(p_minecraft_uuid),
      updated_at=now()
  where id=code_row.user_id
    and mojang_uuid is null;

  update public.minecraft_link_codes
  set used_at=now()
  where id=code_row.id;

  delete from public.minecraft_link_codes
  where user_id=code_row.user_id
    and used_at is null;

  return json_build_object(
    'success',true,
    'user_id',code_row.user_id,
    'minecraft_uuid',lower(p_minecraft_uuid)
  );
end;
$$;

revoke all on function public.bot_touch_user(bigint,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.bot_touch_user(bigint,text,text,text,text,text) to service_role;

revoke all on function public.bot_submit_application(bigint,text,text,date,text,text,text,text) from public,anon,authenticated;
grant execute on function public.bot_submit_application(bigint,text,text,date,text,text,text,text) to service_role;

revoke all on function public.get_user_profile(bigint) from public,anon,authenticated;
grant execute on function public.get_user_profile(bigint) to service_role;

revoke all on function public.bot_create_minecraft_link_code(bigint,text) from public,anon,authenticated;
grant execute on function public.bot_create_minecraft_link_code(bigint,text) to service_role;

revoke all on function public.bot_consume_minecraft_link_code(text,text) from public,anon,authenticated;
grant execute on function public.bot_consume_minecraft_link_code(text,text) to service_role;

delete from public.minecraft_link_codes where expires_at <= now();
