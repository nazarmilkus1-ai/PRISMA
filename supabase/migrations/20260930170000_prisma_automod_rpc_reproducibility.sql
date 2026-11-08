-- PRISMA 2.0.0: restore repository-owned automod bot RPC contracts.
-- These gateways already exist in the live database; this migration makes
-- their definitions reproducible from the repository and keeps them server-only.

create or replace function public.bot_get_automod_config(
  p_chat_id bigint
)
returns json
language sql
security definer
set search_path=''
as $function$
  select json_build_object(
    'settings',
      coalesce(
        (select row_to_json(cs)
         from public.chat_settings cs
         where cs.chat_id = p_chat_id),
        '{}'::json
      ),
    'rules',
      coalesce(
        (select json_agg(ar order by ar.rule_key)
         from public.automod_rules ar
         where ar.chat_id = p_chat_id
           and ar.enabled = true),
        '[]'::json
      )
  );
$function$;

create or replace function public.bot_record_automod_event(
  p_chat_id bigint,
  p_tg_id bigint,
  p_rule_key text,
  p_action text,
  p_score numeric default null,
  p_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $function$
declare
  event_id bigint;
begin
  insert into public.automod_events(
    chat_id,
    telegram_id,
    rule_key,
    action,
    score,
    payload
  )
  values(
    p_chat_id,
    p_tg_id,
    p_rule_key,
    p_action,
    p_score,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;
end;
$function$;

create or replace function public.bot_get_punishment_by_id(
  p_punishment_id uuid
)
returns json
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select json_build_object(
        'id', id,
        'type', type,
        'target_id', target_id,
        'reason', reason,
        'duration_minutes', duration_minutes,
        'expires_at', expires_at,
        'status', status,
        'source', source,
        'created_at', created_at
      )
      from public.moderation_logs
      where id = p_punishment_id
    ),
    json_build_object('error', 'PUNISHMENT_NOT_FOUND')
  );
$function$;

revoke all on function public.bot_get_automod_config(bigint)
from public, anon, authenticated;
grant execute on function public.bot_get_automod_config(bigint)
to service_role;

revoke all on function public.bot_record_automod_event(bigint,bigint,text,text,numeric,jsonb)
from public, anon, authenticated;
grant execute on function public.bot_record_automod_event(bigint,bigint,text,text,numeric,jsonb)
to service_role;

revoke all on function public.bot_get_punishment_by_id(uuid)
from public, anon, authenticated;
grant execute on function public.bot_get_punishment_by_id(uuid)
to service_role;
