-- PRISMA: expose creation state for group onboarding welcome logic.
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
  was_created boolean := false;
  now_ts timestamptz := now();
  ctx text := upper(coalesce(p_context,'GROUP'));
begin
  if p_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;

  select id into uid from public.users where telegram_id=p_tg_id for update;

  if uid is null then
    insert into public.users(
      telegram_id, telegram_username, first_name, last_name, full_name,
      status, is_whitelisted, community_first_seen_at, community_last_seen_at, bot_started_at
    ) values (
      p_tg_id, nullif(trim(p_username),''), nullif(trim(p_first_name),''),
      nullif(trim(p_last_name),''), nullif(trim(p_full_name),''),
      'PENDING', false,
      case when ctx='GROUP' then now_ts else null end,
      case when ctx='GROUP' then now_ts else null end,
      case when ctx='PRIVATE' then now_ts else null end
    ) returning id into uid;
    was_created := true;
  else
    update public.users set
      telegram_username=coalesce(nullif(trim(p_username),''),telegram_username),
      first_name=coalesce(nullif(trim(p_first_name),''),first_name),
      last_name=coalesce(nullif(trim(p_last_name),''),last_name),
      full_name=coalesce(nullif(trim(p_full_name),''),full_name),
      community_first_seen_at=case when ctx='GROUP' then coalesce(community_first_seen_at,now_ts) else community_first_seen_at end,
      community_last_seen_at=case when ctx='GROUP' then now_ts else community_last_seen_at end,
      bot_started_at=case when ctx='PRIVATE' then coalesce(bot_started_at,now_ts) else bot_started_at end,
      updated_at=now_ts
    where id=uid;
  end if;

  return json_build_object(
    'success',true,
    'created',was_created,
    'user_id',uid
  );
end;
$$;

revoke all on function public.bot_touch_user(bigint,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.bot_touch_user(bigint,text,text,text,text,text) to service_role;
