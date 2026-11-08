-- PRISMA v2: claim/lease protocol for the Paper moderation poller.
-- Reading unapplied rows is not enough: overlapping pollers can otherwise apply
-- the same moderation action more than once. A short lease makes claims atomic
-- and recoverable after a crashed plugin instance.

alter table public.moderation_logs
  add column if not exists plugin_processing_at timestamptz;

create index if not exists idx_moderation_logs_plugin_pending
  on public.moderation_logs(created_at asc)
  where applied_at is null
    and type in ('WARN','KICK','MUTE','BAN','UNMUTE','UNBAN','WHITELIST','UNWHITELIST');

create or replace function public.mc_claim_pending_moderation(
  p_limit integer default 100
) returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  lim integer := greatest(1, least(coalesce(p_limit,100),500));
  lease_timeout interval := interval '10 minutes';
  pending json;
begin
  with candidates as (
    select m.id
    from public.moderation_logs m
    where m.applied_at is null
      and m.type in ('WARN','KICK','MUTE','BAN','UNMUTE','UNBAN','WHITELIST','UNWHITELIST')
      and (
        m.plugin_processing_at is null
        or m.plugin_processing_at <= now() - lease_timeout
      )
    order by m.created_at asc
    limit lim
    for update skip locked
  ),
  claimed as (
    update public.moderation_logs m
    set plugin_processing_at=now()
    from candidates c
    where m.id=c.id
    returning m.*
  )
  select coalesce(json_agg(
    json_build_object(
      'id',m.id,
      'type',m.type,
      'reason',m.reason,
      'duration_minutes',m.duration_minutes,
      'expires_at',m.expires_at,
      'target_id',m.target_id,
      'minecraft_nickname',u.minecraft_nickname
    )
    order by m.created_at asc
  ),'[]'::json)
  into pending
  from claimed m
  left join public.users u on u.id=m.target_id;

  return json_build_object('data',pending);
end;
$function$;

create or replace function public.mc_mark_moderation_applied(
  p_log_id uuid
) returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  changed boolean;
begin
  update public.moderation_logs
  set applied_at=coalesce(applied_at,now()),
      plugin_processing_at=null
  where id=p_log_id
    and applied_at is null;

  changed:=found;
  return json_build_object('success',changed,'id',p_log_id);
end;
$function$;

revoke all on function public.mc_claim_pending_moderation(integer)
from public,anon,authenticated;
grant execute on function public.mc_claim_pending_moderation(integer)
to service_role;

revoke all on function public.mc_mark_moderation_applied(uuid)
from public,anon,authenticated;
grant execute on function public.mc_mark_moderation_applied(uuid)
to service_role;
