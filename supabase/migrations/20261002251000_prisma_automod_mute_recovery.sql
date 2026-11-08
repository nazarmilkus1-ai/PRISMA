-- Roll back DB state when Telegram rejects an automatic mute.
-- This prevents users from being marked muted in PRISMA when they can still talk.

create or replace function public.bot_rollback_automod_punishment(
  p_punishment_id uuid,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  target uuid;
  typ text;
  chat bigint;
  still_muted boolean := false;
  has_indefinite_mute boolean := false;
  latest_mute_expiry timestamptz;
begin
  select m.target_id,m.type,m.chat_id
    into target,typ,chat
  from public.moderation_logs m
  where m.id=p_punishment_id
    and m.source_type='AUTOMOD'
    and m.status='ACTIVE'
    and not m.revoked
  for update;

  if target is null then
    return jsonb_build_object('success',false,'reason','PUNISHMENT_NOT_ACTIVE');
  end if;

  if typ <> 'MUTE' then
    return jsonb_build_object('success',false,'reason','UNSUPPORTED_ROLLBACK_TYPE');
  end if;

  update public.moderation_logs
  set status='REVOKED',
      revoked=true,
      revoked_at=now(),
      moderator_note=left(
        concat_ws(E'\n',nullif(moderator_note,''),'Telegram mute failed: '||left(coalesce(p_error,'unknown error'),1500)),
        2000
      )
  where id=p_punishment_id;

  select
    coalesce(bool_or(m.expires_at is null or m.expires_at > now()),false),
    coalesce(bool_or(m.expires_at is null),false),
    max(m.expires_at)
  into still_muted,has_indefinite_mute,latest_mute_expiry
  from public.moderation_logs m
  where m.target_id=target
    and m.type='MUTE'
    and m.status='ACTIVE'
    and not m.revoked
    and (m.expires_at is null or m.expires_at > now());

  update public.users
  set is_muted=still_muted,
      muted_until=case
        when not still_muted then null
        when has_indefinite_mute then null
        else latest_mute_expiry
      end,
      updated_at=now()
  where id=target;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values(
    'user',target,'user.moderation.updated',
    jsonb_build_object(
      'punishment_id',p_punishment_id,
      'type','MUTE',
      'is_muted',still_muted,
      'expires_at',case when has_indefinite_mute then null else latest_mute_expiry end,
      'telegram_apply_failed',true
    )
  );

  return jsonb_build_object('success',true,'rolled_back',p_punishment_id,'is_muted',still_muted);
end;
$function$;

revoke all on function public.bot_rollback_automod_punishment(uuid,text) from public,anon,authenticated;
grant execute on function public.bot_rollback_automod_punishment(uuid,text) to service_role;
