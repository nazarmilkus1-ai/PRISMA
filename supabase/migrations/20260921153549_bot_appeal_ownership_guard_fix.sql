-- Secure appeal creation: the punishment must belong to the caller and be active.
create or replace function public.bot_create_appeal(
  p_tg_id bigint,
  p_reason text,
  p_punishment_id uuid default null
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  uid uuid;
  target_punishment uuid;
  punishment_status text;
  punishment_revoked boolean;
  appeal_id uuid;
begin
  if p_tg_id is null then
    raise exception 'INVALID_TELEGRAM_ID';
  end if;

  if p_reason is null or char_length(trim(p_reason)) not between 10 and 2000 then
    raise exception 'INVALID_REASON';
  end if;

  select u.id
    into uid
  from public.users u
  where u.telegram_id = p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  if p_punishment_id is null then
    select m.id
      into target_punishment
    from public.moderation_logs m
    where m.target_id = uid
      and m.revoked = false
      and upper(coalesce(m.status, '')) = 'ACTIVE'
      and m.type not in ('UNMUTE', 'UNWARN', 'UNBAN', 'WHITELIST', 'UNWHITELIST')
    order by m.created_at desc, m.id desc
    limit 1
    for update;
  else
    select m.id, upper(coalesce(m.status, '')), coalesce(m.revoked, false)
      into target_punishment, punishment_status, punishment_revoked
    from public.moderation_logs m
    where m.id = p_punishment_id
      and m.target_id = uid
    for update;

    if target_punishment is null then
      raise exception 'PUNISHMENT_NOT_FOUND';
    end if;

    if punishment_revoked or punishment_status <> 'ACTIVE' then
      raise exception 'PUNISHMENT_NOT_ACTIVE';
    end if;
  end if;

  if target_punishment is null then
    raise exception 'NO_ACTIVE_PUNISHMENT';
  end if;

  if exists (
    select 1
    from public.punishment_appeals pa
    where pa.user_id = uid
      and pa.punishment_id = target_punishment
      and pa.status in ('OPEN', 'IN_REVIEW')
  ) then
    raise exception 'APPEAL_ALREADY_EXISTS';
  end if;

  insert into public.punishment_appeals(
    user_id,
    telegram_id,
    punishment_id,
    reason,
    status
  )
  values(
    uid,
    p_tg_id,
    target_punishment,
    trim(p_reason),
    'OPEN'
  )
  returning id into appeal_id;

  return json_build_object(
    'success', true,
    'appeal_id', appeal_id,
    'punishment_id', target_punishment
  );
end;
$function$;
