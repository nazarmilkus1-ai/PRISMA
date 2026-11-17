-- Market feature was removed from bot/site/panel in 2.1.0 (#58). Drop its DB objects.
-- All four market_* tables were empty in production when this was written.
-- Forward-only. notification_preferences.market is kept (read by notification preference RPCs).

-- 1) Shared functions: remove market references.
do $fix$
declare
  d text := pg_get_functiondef('private.prisma_participant_global_search(uuid,text)'::regprocedure);
  i int;
  j int;
begin
  d := replace(d, '''wiki'',''[]''::jsonb,''market'',''[]''::jsonb', '''wiki'',''[]''::jsonb');
  i := strpos(d, E',\n    ''market'',coalesce((');
  j := strpos(d, E'\n  );\nend;');
  if i = 0 or j = 0 or j < i then
    raise exception 'global_search: unexpected definition, market block not found';
  end if;
  d := left(d, i - 1) || substr(d, j);
  if d ~* 'market' then
    raise exception 'global_search: market references remain';
  end if;
  execute d;
end
$fix$;

create or replace function public.prisma_run_maintenance()
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  expired int:=0;
  events int:=0;
  metric_rows int:=0;
  activity_rows int:=0;
begin
  expired:=public.expire_punishments();
  events:=public.publish_scheduled_events();

  delete from public.idempotency_keys where expires_at<=now();
  delete from public.login_rate_limits where window_started_at < now()-interval '1 day';

  delete from public.server_metrics
  where recorded_at < now()-interval '30 days';
  get diagnostics metric_rows = row_count;

  delete from public.activity_events
  where created_at < now()-interval '90 days';
  get diagnostics activity_rows = row_count;

  return json_build_object(
    'expired_punishments',expired,
    'events_updated',events,
    'server_metrics_deleted',metric_rows,
    'activity_events_deleted',activity_rows
  );
end;
$function$;

revoke all on function public.prisma_run_maintenance() from public, anon, authenticated;
grant execute on function public.prisma_run_maintenance() to service_role;

-- 2) Drop every function whose name contains "market" (public + private), except nothing is kept.
do $drop$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname in ('public','private') and p.prokind = 'f' and (p.proname like '%market%' or p.proname = 'bot_my_reviewable_offers')
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end
$drop$;

-- 3) Drop tables (children first), module state row.
drop table if exists public.market_reviews cascade;
drop table if exists public.market_offers cascade;
drop table if exists public.market_inquiries cascade;
drop table if exists public.market_listings cascade;

delete from public.prisma_module_states where module_id = 'market';
