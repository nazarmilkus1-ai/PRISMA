-- PRISMA: keep Floodgate/Geyser Bedrock usernames canonical with the configured '.' prefix.
-- Idempotent and additive: normalize existing Bedrock users, then harden the bot RPCs.

update public.users
set minecraft_nickname = '.' || trim(minecraft_nickname),
    updated_at = now()
where platform::text = 'BEDROCK'
  and minecraft_nickname is not null
  and left(trim(minecraft_nickname), 1) <> '.';

create or replace function public.bot_submit_application(
  p_tg_id bigint,
  p_username text,
  p_full_name text,
  p_birth_date date,
  p_minecraft_nick text,
  p_platform text,
  p_goal text,
  p_about text,
  p_phone_number text default null
) returns json
language plpgsql
security definer
set search_path='public' as $$
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

  v_nick := case when v_platform = 'BEDROCK' then '.' || v_raw_nick else v_raw_nick end;

  if exists (
    select 1 from public.users u
    where u.telegram_id <> p_tg_id
      and lower(trim(u.minecraft_nickname)) = lower(v_nick)
  ) then
    raise exception 'MINECRAFT_NICK_TAKEN';
  end if;

  select id into uid from public.users where telegram_id=p_tg_id;

  if uid is null then
    insert into public.users(
      telegram_id, telegram_username, full_name, age,
      minecraft_nickname, platform, phone_number, is_whitelisted, status
    ) values (
      p_tg_id, p_username, p_full_name, age_years,
      v_nick, v_platform::public.platform_type, p_phone_number, false, 'PENDING'
    ) returning id into uid;
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
        minecraft_nickname=v_nick,
        platform=v_platform::public.platform_type,
        phone_number=p_phone_number,
        status='PENDING',
        updated_at=now()
    where id=uid;
  end if;

  insert into public.applications(
    user_id, full_name, age, nickname, platform,
    discovery_source, status, phone_number
  ) values (
    uid, p_full_name, age_years, v_raw_nick,
    v_platform::public.platform_type, 'Telegram', 'PENDING', p_phone_number
  ) returning id into appid;

  insert into public.application_history(application_id,action,actor_tg_id)
  values(appid,'CREATED',p_tg_id);

  return json_build_object(
    'success',true,
    'user_id',uid,
    'application_id',appid,
    'minecraft_nick',v_nick
  );
end;$$;

create or replace function public.bot_change_minecraft_nick(p_tg_id bigint,p_new_nick text)
returns json language plpgsql security definer set search_path='public' as $$
declare
  uid uuid;
  was_whitelisted boolean;
  v_platform text;
  v_raw_nick text;
  v_nick text;
begin
  v_raw_nick := trim(regexp_replace(coalesce(p_new_nick,''), '^\\.', ''));
  if v_raw_nick is null or v_raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then
    raise exception 'INVALID_MINECRAFT_NICK';
  end if;

  select id,is_whitelisted,platform::text
    into uid,was_whitelisted,v_platform
  from public.users
  where telegram_id=p_tg_id;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;

  v_nick := case when upper(coalesce(v_platform,'')) = 'BEDROCK'
    then '.' || v_raw_nick else v_raw_nick end;

  if exists(
    select 1 from public.users
    where id<>uid and lower(trim(minecraft_nickname))=lower(v_nick)
  ) then
    raise exception 'MINECRAFT_NICK_TAKEN';
  end if;

  update public.users
  set minecraft_nickname=v_nick, updated_at=now()
  where id=uid;

  return json_build_object(
    'success',true,
    'minecraft_nick',v_nick,
    'whitelist_sync',was_whitelisted,
    'platform',v_platform
  );
end;$$;

create or replace function public.bot_find_user(p_identifier text)
returns json language plpgsql security definer set search_path='public' as $$
declare
  u record;
  ident text;
  lookup_nick text;
begin
  ident := trim(p_identifier);
  lookup_nick := case when left(ident,1)='.' then ident else '.' || ident end;

  select * into u
  from public.users
  where telegram_id=case when ident ~ '^\\d+$' then ident::bigint else null end
  limit 1;

  if not found then
    select * into u
    from public.users
    where lower(coalesce(telegram_username,''))=lower(ltrim(ident,'@'))
    limit 1;
  end if;

  if not found then
    select * into u
    from public.users
    where lower(coalesce(minecraft_nickname,''))=lower(ident)
       or (platform::text='BEDROCK' and lower(coalesce(minecraft_nickname,''))=lower(lookup_nick))
    limit 1;
  end if;

  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;

  return json_build_object(
    'id',u.id,
    'tg_id',u.telegram_id,
    'username',u.telegram_username,
    'full_name',u.full_name,
    'minecraft_nick',u.minecraft_nickname,
    'is_whitelisted',u.is_whitelisted
  );
end;$$;

grant execute on function public.bot_submit_application(bigint,text,text,date,text,text,text,text,text) to service_role;
grant execute on function public.bot_change_minecraft_nick(bigint,text) to service_role;
grant execute on function public.bot_find_user(text) to service_role;
revoke all on function public.bot_submit_application(bigint,text,text,date,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.bot_change_minecraft_nick(bigint,text) from public,anon,authenticated;
revoke all on function public.bot_find_user(text) from public,anon,authenticated;
