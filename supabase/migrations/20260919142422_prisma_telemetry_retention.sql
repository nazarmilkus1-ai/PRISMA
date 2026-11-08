-- PRISMA telemetry retention: keep operational history bounded.
CREATE OR REPLACE FUNCTION public.prisma_run_maintenance()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
