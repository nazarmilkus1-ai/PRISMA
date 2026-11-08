create or replace function public.bot_revoke_chat_punishment(p_punishment_id uuid,p_admin_tg_id bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  admin_uid uuid;
  target_uid uuid;
  typ text;
begin
  select id into admin_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
  if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
  if not exists(
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=admin_uid and p.key='punishment.remove'
  ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;

  select m.target_id,m.type into target_uid,typ
  from public.moderation_logs m
  where m.id=p_punishment_id and m.chat_id is not null and m.status='ACTIVE' and m.revoked=false
  limit 1;
  if target_uid is null then raise exception 'PUNISHMENT_NOT_FOUND'; end if;

  update public.moderation_logs
  set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED'
  where id=p_punishment_id;

  if typ='WARN' then
    update public.users set warning_count=private.prisma_active_warning_count(target_uid),updated_at=now() where id=target_uid;
  elsif typ='MUTE' then
    update public.users set is_muted=false,muted_until=null,updated_at=now() where id=target_uid;
  elsif typ='BAN' then
    update public.users set is_banned=false,banned_until=null,ban_reason=null,ban_type=null,updated_at=now() where id=target_uid;
  end if;

  insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
  values('user',target_uid,'user.moderation.updated',jsonb_build_object(
    'punishment_id',p_punishment_id,'type','UN'||typ,'warning_count',private.prisma_active_warning_count(target_uid)
  ));

  return json_build_object('success',true,'punishment_id',p_punishment_id,'type',typ,'warning_count',private.prisma_active_warning_count(target_uid));
end;
$function$;

revoke all on function public.bot_revoke_chat_punishment(uuid,bigint) from public,anon,authenticated;
grant execute on function public.bot_revoke_chat_punishment(uuid,bigint) to service_role;