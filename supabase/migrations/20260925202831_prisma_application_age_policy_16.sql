-- Authoritative PRISMA application age policy: 14+.

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
  raw_nick text:=trim(p_minecraft_nick);
  stored_nick text;
  normalized_platform text:=upper(trim(p_platform));
  telegram_id bigint;
begin
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  if p_full_name is null or char_length(trim(p_full_name)) not between 2 and 100 then raise exception 'INVALID_FULL_NAME'; end if;
  if p_birth_date is null or p_birth_date>current_date then raise exception 'INVALID_BIRTH_DATE'; end if;

  age_years:=extract(year from age(current_date,p_birth_date))::integer;
  if age_years<14 then raise exception 'AGE_TOO_YOUNG'; end if;
  if age_years>120 then raise exception 'INVALID_BIRTH_DATE'; end if;
  if raw_nick is null or raw_nick !~ '^[A-Za-z0-9_]{3,16}$' then raise exception 'INVALID_MINECRAFT_NICK'; end if;
  if normalized_platform not in ('JAVA','BEDROCK') then raise exception 'INVALID_PLATFORM'; end if;
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

  stored_nick:=case when normalized_platform='BEDROCK' then '.'||raw_nick else raw_nick end;

  if exists (
    select 1 from public.users u
    where u.id<>uid and u.deleted_at is null
      and lower(trim(u.minecraft_nickname))=lower(stored_nick)
  ) then raise exception 'MINECRAFT_NICK_TAKEN'; end if;

  update public.users
  set full_name=trim(p_full_name),age=age_years,birth_date=p_birth_date,
      minecraft_nickname=stored_nick,
      platform=normalized_platform::public.platform_type,
      status='PENDING',is_whitelisted=false,updated_at=now()
  where id=uid;

  insert into public.applications(
    user_id,full_name,age,nickname,platform,discovery_source,status,
    birth_date,goal,about,cooldown_until
  ) values (
    uid,trim(p_full_name),age_years,raw_nick,normalized_platform::public.platform_type,
    trim(p_discovery_source),'PENDING',p_birth_date,
    nullif(trim(p_goal),''),nullif(trim(p_about),''),null
  ) returning id into appid;

  insert into public.application_history(application_id,action,actor_tg_id)
  values(appid,'CREATED',telegram_id);

  return json_build_object('success',true,'application_id',appid,'user_id',uid);
end;
$function$;
