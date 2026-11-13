-- PRISMA 2.1.0: Bedrock Gamertags with spaces.
-- A Bedrock player types the real Gamertag ("D1lan ok"). Floodgate/Geyser shows that player to the server as
-- ".D1lan_ok" (prefix "." + spaces -> "_", at most 16 characters). We keep BOTH:
--   * users.minecraft_nickname = the server form (what the plugin sees at login; unchanged contract),
--   * users.bedrock_gamertag   = the original Gamertag typed by the player (shown in the UI / bot / panel).
-- Forward-only and additive. Not applied to production by the repository change.

alter table public.users add column if not exists bedrock_gamertag text;
alter table public.users drop constraint if exists users_bedrock_gamertag_len;
alter table public.users add constraint users_bedrock_gamertag_len
  check (bedrock_gamertag is null or char_length(bedrock_gamertag) between 3 and 15) not valid;

-- Original Gamertag -> canonical Gamertag, or null when it cannot be a Floodgate name.
-- Accepts what players really type: leading ".", a modern "#1234" suffix, repeated spaces.
create or replace function private.prisma_bedrock_gamertag(p_raw text)
returns text
language plpgsql
immutable
set search_path=''
as $function$
declare g text;
begin
  g := btrim(coalesce(p_raw,''));
  g := regexp_replace(g, '^\.', '');
  g := regexp_replace(g, '#[0-9]{1,6}$', '');
  g := btrim(regexp_replace(g, '\s+', ' ', 'g'));
  -- 15 = Floodgate's 16-character username limit minus the "." prefix.
  if g !~ '^[A-Za-z0-9_ ]{3,15}$' then return null; end if;
  return g;
end;
$function$;

-- Canonical Gamertag -> the name the server sees.
create or replace function private.prisma_bedrock_server_nick(p_gamertag text)
returns text
language sql
immutable
set search_path=''
as $function$
  select case when p_gamertag is null then null else '.' || replace(p_gamertag, ' ', '_') end;
$function$;

revoke all on function private.prisma_bedrock_gamertag(text) from public,anon,authenticated;
revoke all on function private.prisma_bedrock_server_nick(text) from public,anon,authenticated;
grant execute on function private.prisma_bedrock_gamertag(text) to service_role,authenticated;
grant execute on function private.prisma_bedrock_server_nick(text) to service_role,authenticated;

-- Application creation (site and bot share it).
create or replace function private.prisma_create_application(
  p_user_id uuid,p_full_name text,p_birth_date date,p_minecraft_nick text,
  p_platform text,p_goal text,p_about text,p_discovery_source text
) returns json language plpgsql security definer set search_path=''
as $function$
declare
  uid uuid:=p_user_id;
  appid uuid;
  age_years integer;
  latest_status public.application_status;
  cooldown timestamptz;
  raw_nick text:=btrim(coalesce(p_minecraft_nick,''));
  stored_nick text;
  gamertag text;
  shown_nick text;
  normalized_platform text:=upper(btrim(coalesce(p_platform,'')));
  telegram_id bigint;
begin
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if p_birth_date is null or p_birth_date>current_date then raise exception 'INVALID_BIRTH_DATE'; end if;

  age_years:=extract(year from age(current_date,p_birth_date))::integer;
  if age_years<14 then raise exception 'AGE_TOO_YOUNG'; end if;
  if age_years>120 then raise exception 'INVALID_BIRTH_DATE'; end if;
  if normalized_platform not in ('JAVA','BEDROCK') then raise exception 'INVALID_PLATFORM'; end if;

  if normalized_platform='BEDROCK' then
    gamertag:=private.prisma_bedrock_gamertag(raw_nick);
    if gamertag is null then raise exception 'INVALID_MINECRAFT_NICK'; end if;
    stored_nick:=private.prisma_bedrock_server_nick(gamertag);
    shown_nick:=gamertag;
  else
    if raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;
    stored_nick:=raw_nick;
    shown_nick:=raw_nick;
  end if;

  if trim(coalesce(p_discovery_source,'')) not in
    ('Telegram','TikTok','YouTube','Discord','Рекомендация друга','Другое')
  then raise exception 'INVALID_DISCOVERY_SOURCE'; end if;

  select u.telegram_id into telegram_id
  from public.users u
  where u.id=uid and u.deleted_at is null
  for update;
  if telegram_id is null then raise exception 'TELEGRAM_NOT_LINKED'; end if;

  select a.status,a.cooldown_until into latest_status,cooldown
  from public.applications a
  where a.user_id=uid
  order by a.created_at desc,a.id desc limit 1;

  if latest_status='PENDING' then raise exception 'APPLICATION_PENDING'; end if;
  if latest_status='ACCEPTED' then raise exception 'APPLICATION_ALREADY_ACTIVE'; end if;
  if latest_status='REJECTED' and cooldown is not null and cooldown>now()
    then raise exception 'APPLICATION_COOLDOWN'; end if;

  -- "D1lan ok" and "D1lan_ok" are the same server name, so the comparison is on the server form.
  if exists (
    select 1 from public.users u
    where u.id<>uid and u.deleted_at is null
      and lower(trim(u.minecraft_nickname))=lower(stored_nick)
  ) or exists (
    select 1 from public.user_minecraft_accounts a
    where a.revoked_at is null and a.user_id<>uid
      and lower(btrim(a.minecraft_nickname))=lower(stored_nick)
  ) then raise exception 'MINECRAFT_NICK_TAKEN'; end if;

  update public.users
  set full_name=trim(p_full_name),age=age_years,birth_date=p_birth_date,
      minecraft_nickname=stored_nick,
      bedrock_gamertag=gamertag,
      platform=normalized_platform::public.platform_type,
      status='PENDING',is_whitelisted=false,updated_at=now()
  where id=uid;

  insert into public.applications(
    user_id,full_name,age,nickname,platform,discovery_source,status,
    birth_date,goal,about,cooldown_until
  ) values (
    uid,trim(p_full_name),age_years,shown_nick,normalized_platform::public.platform_type,
    trim(p_discovery_source),'PENDING',p_birth_date,
    nullif(trim(p_goal),''),nullif(trim(p_about),''),null
  ) returning id into appid;

  insert into public.application_history(application_id,action,actor_tg_id)
  values(appid,'CREATED',telegram_id);

  return json_build_object('success',true,'application_id',appid,'user_id',uid);
end;
$function$;

-- Nickname change from the bot (/link).
create or replace function public.bot_change_minecraft_nick(p_tg_id bigint,p_new_nick text)
returns json language plpgsql security definer set search_path='' as $$
declare
  uid uuid;
  was_whitelisted boolean;
  v_platform text;
  v_raw_nick text;
  v_nick text;
  v_gamertag text;
begin
  select id,is_whitelisted,platform::text
    into uid,was_whitelisted,v_platform
  from public.users
  where telegram_id=p_tg_id and deleted_at is null;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;

  v_raw_nick := btrim(coalesce(p_new_nick,''));
  if upper(coalesce(v_platform,'')) = 'BEDROCK' then
    v_gamertag := private.prisma_bedrock_gamertag(v_raw_nick);
    if v_gamertag is null then raise exception 'INVALID_MINECRAFT_NICK'; end if;
    v_nick := private.prisma_bedrock_server_nick(v_gamertag);
  else
    v_raw_nick := regexp_replace(v_raw_nick, '^\.', '');
    if v_raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;
    v_nick := v_raw_nick;
  end if;

  if exists(
    select 1 from public.users
    where id<>uid and deleted_at is null and lower(trim(minecraft_nickname))=lower(v_nick)
  ) or exists(
    select 1 from public.user_minecraft_accounts a
    where a.revoked_at is null and a.user_id<>uid and lower(btrim(a.minecraft_nickname))=lower(v_nick)
  ) then
    raise exception 'MINECRAFT_NICK_TAKEN';
  end if;

  update public.users
  set minecraft_nickname=v_nick, bedrock_gamertag=v_gamertag, updated_at=now()
  where id=uid;

  return json_build_object(
    'success',true,
    'minecraft_nick',v_nick,
    'gamertag',v_gamertag,
    'whitelist_sync',was_whitelisted,
    'platform',v_platform
  );
end;$$;

revoke all on function public.bot_change_minecraft_nick(bigint,text) from public,anon,authenticated;
grant execute on function public.bot_change_minecraft_nick(bigint,text) to service_role;
