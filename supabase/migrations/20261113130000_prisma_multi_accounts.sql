-- PRISMA 2.1.0: one profile, several accounts.
--  * a second Minecraft account on the OTHER platform (Java + Bedrock) joins the same profile: stats, clan,
--    rating, punishments and playtime are shared because the plugin resolves the account to the same user id;
--  * a second Telegram account (alias) acts as the same profile in the bot;
--  * simultaneous play of two accounts of one profile is blocked by the plugin (it knows the shared user id).
-- Forward-only. Not applied to production by the repository change.

create table if not exists public.user_minecraft_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  platform public.platform_type not null,
  minecraft_nickname text not null,   -- the name the server sees (Bedrock: ".D1lan_ok")
  gamertag text,                      -- original Bedrock Gamertag ("D1lan ok"), null for Java
  minecraft_uuid uuid,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint user_minecraft_accounts_nick_len check (char_length(btrim(minecraft_nickname)) between 3 and 32)
);
create unique index if not exists user_minecraft_accounts_one_per_platform
  on public.user_minecraft_accounts(user_id, platform) where revoked_at is null;
create unique index if not exists user_minecraft_accounts_nick_unique
  on public.user_minecraft_accounts(lower(btrim(minecraft_nickname))) where revoked_at is null;
create unique index if not exists user_minecraft_accounts_uuid_unique
  on public.user_minecraft_accounts(minecraft_uuid) where minecraft_uuid is not null and revoked_at is null;
alter table public.user_minecraft_accounts enable row level security;
revoke all on public.user_minecraft_accounts from public, anon, authenticated;
grant select, insert, update, delete on public.user_minecraft_accounts to service_role;

create table if not exists public.user_telegram_aliases (
  telegram_id bigint primary key,
  user_id uuid not null unique references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.user_telegram_aliases enable row level security;
revoke all on public.user_telegram_aliases from public, anon, authenticated;
grant select, insert, update, delete on public.user_telegram_aliases to service_role;

-- ---------------------------------------------------------------- plugin identity (alias aware)
create or replace function public.get_minecraft_user_v2(
  p_nickname text,
  p_minecraft_uuid uuid
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  result_row public.users%rowtype;
  account public.user_minecraft_accounts%rowtype;
begin
  if p_nickname is null or btrim(p_nickname)='' then
    return json_build_object('error','INVALID_MINECRAFT_NICK');
  end if;
  if p_minecraft_uuid is null then
    return json_build_object('error','INVALID_MINECRAFT_UUID');
  end if;

  select * into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_nickname))
  limit 1;

  if not found then
    -- Not a primary account: maybe the profile's second (other-platform) account.
    select * into account
    from public.user_minecraft_accounts
    where revoked_at is null
      and lower(btrim(minecraft_nickname))=lower(btrim(p_nickname))
    limit 1;
    if account.id is null then
      return json_build_object('error','USER_NOT_FOUND');
    end if;
    select * into result_row from public.users where id=account.user_id and deleted_at is null;
    if not found then
      return json_build_object('error','USER_NOT_FOUND');
    end if;
    if account.minecraft_uuid is not null and account.minecraft_uuid<>p_minecraft_uuid then
      return json_build_object('error','MINECRAFT_UUID_MISMATCH');
    end if;
    return json_build_object(
      'id',result_row.id,
      'telegram_id',result_row.telegram_id,
      'minecraft_nickname',account.minecraft_nickname,
      'minecraft_uuid',account.minecraft_uuid,
      'clan_id',result_row.clan_id,
      'is_muted',result_row.is_muted,
      'muted_until',result_row.muted_until,
      'status',result_row.status,
      'platform',account.platform,
      'is_whitelisted',result_row.is_whitelisted,
      'is_banned',result_row.is_banned,
      'ban_reason',result_row.ban_reason,
      'account_kind','SECONDARY'
    );
  end if;

  if result_row.minecraft_uuid is not null
     and result_row.minecraft_uuid <> p_minecraft_uuid then
    return json_build_object('error','MINECRAFT_UUID_MISMATCH');
  end if;

  return json_build_object(
    'id',result_row.id,
    'telegram_id',result_row.telegram_id,
    'minecraft_nickname',result_row.minecraft_nickname,
    'minecraft_uuid',result_row.minecraft_uuid,
    'clan_id',result_row.clan_id,
    'is_muted',result_row.is_muted,
    'muted_until',result_row.muted_until,
    'status',result_row.status,
    'platform',result_row.platform,
    'is_whitelisted',result_row.is_whitelisted,
    'is_banned',result_row.is_banned,
    'ban_reason',result_row.ban_reason,
    'account_kind','PRIMARY'
  );
end;
$function$;

create or replace function public.mc_bind_minecraft_identity(
  p_nickname text,
  p_minecraft_uuid uuid,
  p_platform text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  result_row public.users%rowtype;
  account public.user_minecraft_accounts%rowtype;
  normalized_platform text;
begin
  normalized_platform := upper(btrim(coalesce(p_platform, '')));
  if normalized_platform not in ('JAVA', 'BEDROCK') then
    return json_build_object('error', 'INVALID_PLATFORM');
  end if;
  if p_nickname is null or btrim(p_nickname) = '' then
    return json_build_object('error', 'INVALID_MINECRAFT_NICK');
  end if;
  if p_minecraft_uuid is null then
    return json_build_object('error', 'INVALID_MINECRAFT_UUID');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_minecraft_uuid::text));

  select * into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname)) = lower(trim(p_nickname))
  for update;

  if not found then
    -- Second account of a profile: bind its UUID the same way.
    select * into account
    from public.user_minecraft_accounts
    where revoked_at is null
      and lower(btrim(minecraft_nickname))=lower(btrim(p_nickname))
    for update;
    if account.id is null then
      return json_build_object('error', 'USER_NOT_FOUND');
    end if;
    if account.minecraft_uuid is not null and account.minecraft_uuid <> p_minecraft_uuid then
      return json_build_object('error', 'MINECRAFT_UUID_MISMATCH');
    end if;
    if account.platform::text <> normalized_platform then
      return json_build_object('error', 'PLATFORM_MISMATCH');
    end if;
    if exists (select 1 from public.users u where u.deleted_at is null and u.minecraft_uuid = p_minecraft_uuid)
       or exists (select 1 from public.user_minecraft_accounts o
                  where o.revoked_at is null and o.id <> account.id and o.minecraft_uuid = p_minecraft_uuid) then
      return json_build_object('error', 'MINECRAFT_UUID_ALREADY_BOUND');
    end if;
    update public.user_minecraft_accounts set minecraft_uuid = p_minecraft_uuid where id = account.id
    returning * into account;
    select * into result_row from public.users where id = account.user_id;
    return json_build_object(
      'id', result_row.id, 'telegram_id', result_row.telegram_id,
      'minecraft_nickname', account.minecraft_nickname, 'minecraft_uuid', account.minecraft_uuid,
      'clan_id', result_row.clan_id, 'is_muted', result_row.is_muted, 'muted_until', result_row.muted_until,
      'status', result_row.status, 'platform', account.platform,
      'is_whitelisted', result_row.is_whitelisted, 'is_banned', result_row.is_banned, 'ban_reason', result_row.ban_reason
    );
  end if;

  if result_row.minecraft_uuid is not null
     and result_row.minecraft_uuid <> p_minecraft_uuid then
    return json_build_object('error', 'MINECRAFT_UUID_MISMATCH');
  end if;
  if result_row.platform is not null
     and result_row.platform::text <> normalized_platform then
    return json_build_object('error', 'PLATFORM_MISMATCH');
  end if;
  if exists (
    select 1 from public.users other_user
    where other_user.deleted_at is null
      and other_user.id <> result_row.id
      and other_user.minecraft_uuid = p_minecraft_uuid
  ) or exists (
    select 1 from public.user_minecraft_accounts o
    where o.revoked_at is null and o.minecraft_uuid = p_minecraft_uuid
  ) then
    return json_build_object('error', 'MINECRAFT_UUID_ALREADY_BOUND');
  end if;

  update public.users
  set minecraft_uuid = p_minecraft_uuid,
      platform = normalized_platform::public.platform_type
  where id = result_row.id
  returning * into result_row;

  return json_build_object(
    'id', result_row.id, 'telegram_id', result_row.telegram_id,
    'minecraft_nickname', result_row.minecraft_nickname, 'minecraft_uuid', result_row.minecraft_uuid,
    'clan_id', result_row.clan_id, 'is_muted', result_row.is_muted, 'muted_until', result_row.muted_until,
    'status', result_row.status, 'platform', result_row.platform,
    'is_whitelisted', result_row.is_whitelisted, 'is_banned', result_row.is_banned, 'ban_reason', result_row.ban_reason
  );
end;
$function$;

-- ---------------------------------------------------------------- bot: second Minecraft account
create or replace function public.bot_add_minecraft_account(
  p_tg_id bigint,
  p_platform text,
  p_nickname text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  profile public.users%rowtype;
  normalized_platform text := upper(btrim(coalesce(p_platform,'')));
  nick text := btrim(coalesce(p_nickname,''));
  gamertag text;
begin
  if normalized_platform not in ('JAVA','BEDROCK') then return json_build_object('error','INVALID_PLATFORM'); end if;
  if normalized_platform='JAVA' then
    if nick !~ '^[A-Za-z0-9_]{3,16}$' then return json_build_object('error','INVALID_MINECRAFT_NICK'); end if;
  else
    gamertag := private.prisma_bedrock_gamertag(nick);
    if gamertag is null then return json_build_object('error','INVALID_MINECRAFT_NICK'); end if;
    nick := private.prisma_bedrock_server_nick(gamertag);
  end if;

  select * into profile from public.users
  where telegram_id=p_tg_id and deleted_at is null for update;
  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;
  if profile.status<>'ACCEPTED' or not coalesce(profile.is_whitelisted,false) then return json_build_object('error','NOT_ACCEPTED'); end if;
  if coalesce(profile.is_banned,false) then return json_build_object('error','BANNED'); end if;
  if profile.platform is null or profile.platform::text=normalized_platform then
    -- The extra account must be on the OTHER platform than the primary one.
    return json_build_object('error','SAME_PLATFORM');
  end if;

  if exists (select 1 from public.users u where u.deleted_at is null and lower(btrim(u.minecraft_nickname))=lower(nick))
     or exists (select 1 from public.user_minecraft_accounts a where a.revoked_at is null and lower(btrim(a.minecraft_nickname))=lower(nick)) then
    return json_build_object('error','NICKNAME_TAKEN');
  end if;
  if exists (select 1 from public.user_minecraft_accounts a where a.user_id=profile.id and a.revoked_at is null) then
    return json_build_object('error','ACCOUNT_LIMIT');
  end if;

  insert into public.user_minecraft_accounts(user_id,platform,minecraft_nickname,gamertag)
  values(profile.id,normalized_platform::public.platform_type,nick,gamertag);
  return json_build_object('success',true,'platform',normalized_platform,'nickname',nick,'gamertag',gamertag);
end;
$function$;

create or replace function public.bot_remove_minecraft_account(p_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid; changed integer;
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null;
  if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;
  update public.user_minecraft_accounts set revoked_at=now() where user_id=uid and revoked_at is null;
  get diagnostics changed = row_count;
  return json_build_object('success',true,'removed',changed);
end;
$function$;

create or replace function public.bot_list_minecraft_accounts(p_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare profile public.users%rowtype; extra json;
begin
  select * into profile from public.users where telegram_id=p_tg_id and deleted_at is null;
  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;
  select coalesce(json_agg(json_build_object('platform',a.platform,'nickname',a.minecraft_nickname,'gamertag',a.gamertag,'bound',a.minecraft_uuid is not null)),'[]'::json)
  into extra from public.user_minecraft_accounts a where a.user_id=profile.id and a.revoked_at is null;
  return json_build_object('primary',json_build_object('platform',profile.platform,'nickname',profile.minecraft_nickname,'gamertag',profile.bedrock_gamertag),'extra',extra);
end;
$function$;

-- ---------------------------------------------------------------- bot: second Telegram account
create or replace function public.bot_telegram_alias_create(p_primary_tg bigint, p_alias_tg bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid;
begin
  if p_primary_tg is null or p_alias_tg is null or p_primary_tg=p_alias_tg then return json_build_object('error','INVALID_ACCOUNT'); end if;
  select id into uid from public.users
  where telegram_id=p_primary_tg and deleted_at is null and status='ACCEPTED' and not coalesce(is_banned,false);
  if uid is null then return json_build_object('error','PRIMARY_NOT_ACCEPTED'); end if;
  -- A Telegram group sighting creates a lightweight PENDING row (no application, no Minecraft account).
  -- That is not a real profile: drop it so the account can become an alias. A real profile blocks the link.
  if exists (select 1 from public.users u where u.telegram_id=p_alias_tg) then
    begin
      delete from public.users u
      where u.telegram_id=p_alias_tg and u.status='PENDING'
        and u.minecraft_nickname is null and u.minecraft_uuid is null
        and not exists (select 1 from public.applications a where a.user_id=u.id);
    exception when foreign_key_violation then
      return json_build_object('error','ALIAS_HAS_OWN_PROFILE');
    end;
    if exists (select 1 from public.users u where u.telegram_id=p_alias_tg) then
      return json_build_object('error','ALIAS_HAS_OWN_PROFILE');
    end if;
  end if;
  if exists (select 1 from public.user_telegram_aliases a where a.telegram_id=p_alias_tg) then
    return json_build_object('error','ALIAS_ALREADY_LINKED');
  end if;
  if exists (select 1 from public.user_telegram_aliases a where a.user_id=uid) then
    return json_build_object('error','ALIAS_LIMIT');
  end if;
  insert into public.user_telegram_aliases(telegram_id,user_id) values(p_alias_tg,uid);
  return json_build_object('success',true);
end;
$function$;

create or replace function public.bot_telegram_alias_resolve(p_tg bigint)
returns bigint
language sql
security definer
set search_path=''
stable
as $function$
  select u.telegram_id
  from public.user_telegram_aliases a
  join public.users u on u.id=a.user_id and u.deleted_at is null
  where a.telegram_id=p_tg
  limit 1;
$function$;

create or replace function public.bot_telegram_alias_remove(p_primary_tg bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare removed integer;
begin
  delete from public.user_telegram_aliases a
  using public.users u
  where a.user_id=u.id and u.telegram_id=p_primary_tg;
  get diagnostics removed = row_count;
  return json_build_object('success',true,'removed',removed);
end;
$function$;

revoke all on function public.get_minecraft_user_v2(text,uuid) from public,anon,authenticated;
revoke all on function public.mc_bind_minecraft_identity(text,uuid,text) from public,anon,authenticated;
revoke all on function public.bot_add_minecraft_account(bigint,text,text) from public,anon,authenticated;
revoke all on function public.bot_remove_minecraft_account(bigint) from public,anon,authenticated;
revoke all on function public.bot_list_minecraft_accounts(bigint) from public,anon,authenticated;
revoke all on function public.bot_telegram_alias_create(bigint,bigint) from public,anon,authenticated;
revoke all on function public.bot_telegram_alias_resolve(bigint) from public,anon,authenticated;
revoke all on function public.bot_telegram_alias_remove(bigint) from public,anon,authenticated;
grant execute on function public.get_minecraft_user_v2(text,uuid) to service_role;
grant execute on function public.mc_bind_minecraft_identity(text,uuid,text) to service_role;
grant execute on function public.bot_add_minecraft_account(bigint,text,text) to service_role;
grant execute on function public.bot_remove_minecraft_account(bigint) to service_role;
grant execute on function public.bot_list_minecraft_accounts(bigint) to service_role;
grant execute on function public.bot_telegram_alias_create(bigint,bigint) to service_role;
grant execute on function public.bot_telegram_alias_resolve(bigint) to service_role;
grant execute on function public.bot_telegram_alias_remove(bigint) to service_role;
