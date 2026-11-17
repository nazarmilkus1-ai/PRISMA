-- Part 2/2. When the term ends the ban is NOT lifted automatically: it waits for an admin to confirm the return
-- (or keep the ban). Plus Telegram activity candidates (fewer than N messages in 7 days). Applied as 20261117144258.
-- Forward-only.

-- 2) Expiry: warns and mutes expire as before; bans move to "waiting for admin confirmation".
create or replace function public.expire_punishments()
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  affected integer:=0;
  review_rows integer:=0;
  user_rows integer:=0;
begin
  update public.moderation_logs
  set status='EXPIRED'
  where status='ACTIVE' and type<>'BAN' and expires_at is not null and expires_at<=now();
  get diagnostics affected=row_count;

  update public.users
  set ban_type='REVIEW',
      banned_until=null,
      ban_review_due_at=now(),
      ban_review_notified_at=null,
      updated_at=now()
  where is_banned and banned_until is not null and banned_until<=now();
  get diagnostics review_rows=row_count;

  update public.users
  set
    is_muted=case when muted_until is not null and muted_until<=now() then false else is_muted end,
    muted_until=case when muted_until is not null and muted_until<=now() then null else muted_until end,
    warning_count=private.prisma_active_warning_count(users.id),
    updated_at=now()
  where
    (muted_until is not null and muted_until<=now())
    or warning_count<>private.prisma_active_warning_count(users.id);
  get diagnostics user_rows=row_count;

  return affected+review_rows+user_rows;
end;
$function$;

-- 3) Lifting a ban also works on a ban that is waiting for confirmation, and clears the review flags.
do $fix$
declare
  d text := pg_get_functiondef('public.bot_lift_punishment(bigint,text,bigint)'::regprocedure);
  d2 text;
begin
  d2 := replace(d, 'and (m.expires_at is null or m.expires_at > now())',
                   'and (typ = ''BAN'' or m.expires_at is null or m.expires_at > now())');
  if d2 = d then raise exception 'bot_lift_punishment: expiry condition not found'; end if;
  d := d2;
  d2 := replace(d, E'ban_type = null,\n        is_whitelisted',
                   E'ban_type = null,\n        ban_review_due_at = null,\n        ban_review_notified_at = null,\n        is_whitelisted');
  if d2 = d then raise exception 'bot_lift_punishment: ban update not found'; end if;
  execute d2;
end
$fix$;

-- 4) Review queue for the bot.
create or replace function public.bot_ban_review_claim(p_limit integer default 20)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  result json;
begin
  with picked as (
    select u.id from public.users u
    where u.is_banned and u.ban_type='REVIEW' and u.ban_review_notified_at is null and u.deleted_at is null
    order by u.ban_review_due_at
    limit greatest(1,least(coalesce(p_limit,20),50))
    for update skip locked
  ),
  upd as (
    update public.users u set ban_review_notified_at=now()
    from picked where u.id=picked.id
    returning u.telegram_id,u.minecraft_nickname,u.ban_reason,u.ban_review_due_at
  )
  select coalesce(json_agg(json_build_object(
    'tg_id',telegram_id,'nickname',minecraft_nickname,'reason',ban_reason,'due_at',ban_review_due_at
  ) order by ban_review_due_at),'[]'::json) into result from upd;
  return result;
end;
$function$;

create or replace function public.bot_ban_review_list()
returns json
language sql
security definer
set search_path=''
as $function$
  select coalesce(json_agg(json_build_object(
    'tg_id',u.telegram_id,'nickname',u.minecraft_nickname,'reason',u.ban_reason,'due_at',u.ban_review_due_at
  ) order by u.ban_review_due_at),'[]'::json)
  from public.users u
  where u.is_banned and u.ban_type='REVIEW' and u.deleted_at is null;
$function$;

-- Admin keeps the ban after the term ended (it then stays until an admin lifts it).
create or replace function public.bot_ban_review_keep(p_user_tg_id bigint, p_admin_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  admin_uid uuid;
begin
  select a.user_id into admin_uid
  from public.admins a join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id and u.deleted_at is null limit 1;
  if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  if not private.prisma_has_user_permission(admin_uid,'punishment.ban') then
    raise exception 'ADMIN_LACKS_PERMISSION';
  end if;

  select id into uid from public.users
  where telegram_id=p_user_tg_id and deleted_at is null and is_banned and ban_type='REVIEW'
  for update;
  if uid is null then raise exception 'NO_BAN_AWAITING_REVIEW'; end if;

  update public.users
  set ban_type='PERMANENT',ban_review_due_at=null,ban_review_notified_at=null,updated_at=now()
  where id=uid;
  return json_build_object('success',true);
end;
$function$;

-- 5) Telegram activity: fewer than p_min_messages messages during the last p_days days.
create or replace function public.bot_weekly_telegram_inactivity_candidates(p_days integer default 7, p_min_messages integer default 50)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  since_date date;
  players_count integer;
  rows_data json;
begin
  if p_days is null or p_days<1 or p_days>31 then raise exception 'INVALID_WINDOW'; end if;
  if p_min_messages is null or p_min_messages<1 or p_min_messages>100000 then raise exception 'INVALID_THRESHOLD'; end if;
  since_date := (now()-make_interval(days=>p_days-1))::date;

  select count(distinct a.user_id) into players_count
  from public.telegram_chat_activity a
  where a.activity_date>=since_date and a.message_count>0;

  with msgs as (
    select a.user_id,sum(a.message_count)::integer as n
    from public.telegram_chat_activity a
    where a.activity_date>=since_date
    group by a.user_id
  )
  select coalesce(json_agg(json_build_object(
           'tg_id',u.telegram_id,
           'nickname',coalesce(u.minecraft_nickname,u.telegram_username),
           'messages',coalesce(m.n,0),
           'active_warns',private.prisma_active_warning_count(u.id)
         ) order by coalesce(m.n,0),u.minecraft_nickname),'[]'::json)
  into rows_data
  from public.users u
  left join msgs m on m.user_id=u.id
  where u.deleted_at is null
    and u.status='ACCEPTED'
    and not coalesce(u.is_banned,false)
    and u.telegram_id is not null
    and u.created_at<now()-interval '7 days'
    and not exists (select 1 from public.admins a where a.user_id=u.id)
    and coalesce(m.n,0)<p_min_messages
    and not exists (
      select 1 from public.moderation_logs l
      where l.target_id=u.id
        and l.source_type='AUTO_TG_INACTIVITY'
        and l.created_at>now()-interval '6 days'
    );

  return json_build_object('window_days',p_days,'min_messages',p_min_messages,'players',players_count,'candidates',rows_data);
end;
$function$;

revoke all on function public.expire_punishments() from public, anon, authenticated;
grant execute on function public.expire_punishments() to service_role;
revoke all on function public.bot_ban_review_claim(integer) from public, anon, authenticated;
grant execute on function public.bot_ban_review_claim(integer) to service_role;
revoke all on function public.bot_ban_review_list() from public, anon, authenticated;
grant execute on function public.bot_ban_review_list() to service_role;
revoke all on function public.bot_ban_review_keep(bigint,bigint) from public, anon, authenticated;
grant execute on function public.bot_ban_review_keep(bigint,bigint) to service_role;
revoke all on function public.bot_weekly_telegram_inactivity_candidates(integer,integer) from public, anon, authenticated;
grant execute on function public.bot_weekly_telegram_inactivity_candidates(integer,integer) to service_role;
