-- PRISMA v2 application decision core.
-- Bot and Admin use the same transactional decision function.
-- Existing public bot RPC signatures are preserved for compatibility.

create or replace function private.prisma_decide_application(
  p_application_id uuid,
  p_actor_user_id uuid,
  p_action text,
  p_reason text default null
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare
  aid uuid;
  uid uuid;
  actor_tg_id bigint;
  actor_name text;
  normalized_action text := lower(trim(p_action));
  v_reason text := left(nullif(trim(p_reason),''),2000);
  new_status public.application_status;
  cooldown timestamptz;
begin
  if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if normalized_action not in ('approve','reject') then raise exception 'INVALID_ACTION'; end if;

  select a.id,a.user_id
    into aid,uid
  from public.applications a
  where a.id=p_application_id
    and a.status='PENDING'
    and not a.is_archived
  for update;

  if aid is null then raise exception 'APPLICATION_NOT_FOUND'; end if;

  select u.telegram_id, coalesce(u.full_name, nullif(trim(concat_ws(' ',u.first_name,u.last_name)),''), u.telegram_username)
    into actor_tg_id, actor_name
  from public.users u
  join public.admins ad on ad.user_id=u.id
  join public.role_permissions rp on rp.role_id=ad.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.id=p_actor_user_id
    and p.key=case when normalized_action='approve' then 'application.approve' else 'application.reject' end
    and u.deleted_at is null
  limit 1;

  if actor_tg_id is null then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  if normalized_action='approve' then
    new_status='ACCEPTED';
    cooldown=null;
    update public.applications
    set status=new_status,
        rejection_reason=null,
        reviewed_by_tg_id=actor_tg_id,
        reviewed_by_name=actor_name,
        reviewed_at=now(),
        cooldown_until=null,
        updated_at=now()
    where id=aid;

    update public.users
    set status='ACCEPTED',
        is_whitelisted=true,
        updated_at=now()
    where id=uid;

    insert into public.application_history(application_id,action,actor_tg_id,reason)
    values(aid,'APPROVED',actor_tg_id,null);
  else
    new_status='REJECTED';
    cooldown=now()+interval '7 days';
    update public.applications
    set status=new_status,
        rejection_reason=v_reason,
        reviewed_by_tg_id=actor_tg_id,
        reviewed_by_name=actor_name,
        reviewed_at=now(),
        cooldown_until=cooldown,
        updated_at=now()
    where id=aid;

    update public.users
    set status='REJECTED',
        is_whitelisted=false,
        updated_at=now()
    where id=uid;

    insert into public.application_history(application_id,action,actor_tg_id,reason)
    values(aid,'REJECTED',actor_tg_id,v_reason);
  end if;

  return json_build_object(
    'success',true,
    'application_id',aid,
    'user_id',uid,
    'status',new_status,
    'actor_user_id',p_actor_user_id,
    'actor_tg_id',actor_tg_id,
    'cooldown_until',cooldown
  );
end;
$prisma$;

create or replace function public.bot_approve_application(
  p_application_id uuid,
  p_admin_tg_id bigint
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare actor_id uuid;
begin
  select u.id into actor_id
  from public.users u
  where u.telegram_id=p_admin_tg_id and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  return private.prisma_decide_application(p_application_id,actor_id,'approve',null);
end;
$prisma$;

create or replace function public.bot_reject_application(
  p_application_id uuid,
  p_admin_tg_id bigint,
  p_reason text default null
) returns json
language plpgsql
security definer
set search_path=''
as $prisma$
declare actor_id uuid;
begin
  select u.id into actor_id
  from public.users u
  where u.telegram_id=p_admin_tg_id and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  return private.prisma_decide_application(p_application_id,actor_id,'reject',p_reason);
end;
$prisma$;

revoke all on function private.prisma_decide_application(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.prisma_decide_application(uuid,uuid,text,text) to service_role;

revoke all on function public.bot_approve_application(uuid,bigint) from public,anon,authenticated;
grant execute on function public.bot_approve_application(uuid,bigint) to service_role;

revoke all on function public.bot_reject_application(uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_reject_application(uuid,bigint,text) to service_role;
