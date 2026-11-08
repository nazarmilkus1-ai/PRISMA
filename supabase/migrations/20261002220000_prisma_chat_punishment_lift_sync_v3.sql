create or replace function public.bot_lift_chat_punishment(p_chat_id bigint,p_user_tg_id bigint,p_type text,p_admin_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
  admin_uid uuid;
  pid uuid;
  typ text:=upper(trim(p_type));
  warning_count_now integer:=0;
begin
  select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null limit 1;
  select id into admin_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;

  if not exists(
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=admin_uid and p.key='punishment.remove'
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  select m.id into pid
  from public.moderation_logs m
  where m.chat_id=p_chat_id and m.target_id=uid and m.type=typ
    and m.status='ACTIVE' and m.revoked=false
    and (m.expires_at is null or m.expires_at>now())
  order by m.created_at desc limit 1;

  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED'
  where id=pid;

  if typ='WARN' then
    warning_count_now:=private.prisma_active_warning_count(uid);
    update public.users set warning_count=warning_count_now,updated_at=now() where id=uid;
  elsif typ='MUTE' then
    update public.users set is_muted=false,muted_until=null,updated_at=now() where id=uid;
  elsif typ='BAN' then
    update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,updated_at=now() where id=uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',pid,'type','UN'||typ,'warning_count',private.prisma_active_warning_count(uid)
  ));

  return json_build_object(
    'success',true,'punishment_id',pid,'type',typ,
    'warning_count',private.prisma_active_warning_count(uid)
  );
end;
$function$;

revoke all on function public.bot_lift_chat_punishment(bigint,bigint,text,bigint) from public,anon,authenticated;
grant execute on function public.bot_lift_chat_punishment(bigint,bigint,text,bigint) to service_role;