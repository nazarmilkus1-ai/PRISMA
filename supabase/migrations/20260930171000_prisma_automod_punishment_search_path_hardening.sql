-- PRISMA 2.0.0: normalize the remaining automod SECURITY DEFINER gateway.

create or replace function public.bot_apply_automod_punishment(
  p_chat_id bigint,
  p_user_tg_id bigint,
  p_type text,
  p_reason text,
  p_duration integer default null,
  p_rule_key text default 'automod',
  p_payload jsonb default '{}'::jsonb
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  pid uuid;
  expires timestamptz;
begin
  if not exists (
    select 1 from public.chat_settings cs where cs.chat_id = p_chat_id
  ) then
    raise exception 'AUTOMOD_CHAT_NOT_CONFIGURED';
  end if;

  select id into uid
  from public.users
  where telegram_id = p_user_tg_id
    and deleted_at is null;

  if uid is null then
    return json_build_object('success', true, 'user_found', false);
  end if;

  if lower(p_type) not in ('warn', 'mute', 'ban') then
    raise exception 'UNSUPPORTED_AUTOMOD_PUNISHMENT';
  end if;

  if p_duration is not null and (p_duration <= 0 or p_duration > 10080) then
    raise exception 'INVALID_DURATION';
  end if;

  expires := case
    when p_duration is not null then now() + make_interval(mins => p_duration)
    else null
  end;

  insert into public.moderation_logs(
    target_id,
    issued_by_tg_id,
    issued_by_name,
    type,
    reason,
    duration_minutes,
    expires_at,
    source,
    source_type,
    evidence,
    applied_at,
    status
  )
  values(
    uid,
    null,
    'PRISMA AUTOMOD',
    upper(p_type),
    trim(p_reason),
    p_duration,
    expires,
    'BOT',
    'AUTOMOD',
    jsonb_build_array(
      jsonb_build_object(
        'chat_id', p_chat_id,
        'rule_key', p_rule_key,
        'payload', coalesce(p_payload, '{}'::jsonb)
      )
    ),
    null,
    'ACTIVE'
  )
  returning id into pid;

  if lower(p_type) = 'warn' then
    update public.users
    set warning_count = coalesce(warning_count, 0) + 1,
        updated_at = now()
    where id = uid;
  elsif lower(p_type) = 'mute' then
    update public.users
    set is_muted = true,
        muted_until = expires,
        updated_at = now()
    where id = uid;
  elsif lower(p_type) = 'ban' then
    update public.users
    set is_banned = true,
        banned_until = expires,
        ban_reason = trim(p_reason),
        is_whitelisted = false,
        updated_at = now()
    where id = uid;
  end if;

  insert into public.sync_outbox(
    aggregate_type,
    aggregate_id,
    event_type,
    payload
  )
  values(
    'user',
    uid,
    'user.moderation.updated',
    jsonb_build_object(
      'punishment_id', pid,
      'type', upper(p_type),
      'expires_at', expires
    )
  );

  return json_build_object(
    'success', true,
    'user_found', true,
    'punishment_id', pid,
    'expires_at', expires
  );
end;
$function$;

revoke all on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text,jsonb)
from public, anon, authenticated;

grant execute on function public.bot_apply_automod_punishment(bigint,bigint,text,text,integer,text,jsonb)
to service_role;
