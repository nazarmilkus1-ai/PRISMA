-- PRISMA v2 report moderation transaction.
-- Staff route uses service-role adapter after requireAdminContext has authorized the caller.

create or replace function private.prisma_update_report(
  p_report_id uuid,
  p_actor_user_id uuid,
  p_status text,
  p_internal_notes text default null,
  p_assigned_to uuid default null,
  p_involved_players jsonb default null
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare
  rid uuid;
  old_status public.report_status;
  old_assigned uuid;
  admin_id uuid;
  next_status public.report_status;
  note text;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if upper(trim(p_status)) not in ('OPEN','IN_REVIEW','RESOLVED','DISMISSED') then raise exception 'INVALID_STATUS'; end if;
  next_status=upper(trim(p_status))::public.report_status;

  select r.id,r.status,r.assigned_to into rid,old_status,old_assigned
  from public.reports r where r.id=p_report_id for update;
  if rid is null then raise exception 'REPORT_NOT_FOUND'; end if;

  select ad.id into admin_id
  from public.admins ad
  join public.role_permissions rp on rp.role_id=ad.role_id
  join public.permissions p on p.id=rp.permission_id
  where ad.user_id=p_actor_user_id
    and p.key=case when next_status='DISMISSED' then 'report.reject' else 'report.resolve' end
  limit 1;
  if admin_id is null then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  note=left(nullif(trim(p_internal_notes),''),5000);

  update public.reports
  set status=next_status,
      internal_notes=coalesce(note,internal_notes),
      assigned_to=case when p_assigned_to is null then assigned_to else p_assigned_to end,
      involved_players=coalesce(p_involved_players,involved_players),
      resolved_at=case when next_status in ('RESOLVED','DISMISSED') then now() else null end,
      updated_at=now()
  where id=rid;

  insert into public.report_history(
    report_id,actor_admin_id,from_status,to_status,from_assignee,to_assignee,note
  ) values (
    rid,admin_id,old_status,next_status,old_assigned,
    case when p_assigned_to is null then old_assigned else p_assigned_to end,
    note
  );

  return json_build_object(
    'success',true,'report_id',rid,'from_status',old_status,'status',next_status,
    'assigned_to',case when p_assigned_to is null then old_assigned else p_assigned_to end,
    'admin_id',admin_id
  );
end;
$prisma$;

revoke all on function private.prisma_update_report(uuid,uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.prisma_update_report(uuid,uuid,text,text,uuid,jsonb) to service_role;

create or replace function public.staff_update_report(
  p_report_id uuid,
  p_actor_user_id uuid,
  p_status text,
  p_internal_notes text default null,
  p_assigned_to uuid default null,
  p_involved_players jsonb default null
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
begin
  return private.prisma_update_report(
    p_report_id,p_actor_user_id,p_status,p_internal_notes,p_assigned_to,p_involved_players
  );
end;
$prisma$;

revoke all on function public.staff_update_report(uuid,uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.staff_update_report(uuid,uuid,text,text,uuid,jsonb) to service_role;
