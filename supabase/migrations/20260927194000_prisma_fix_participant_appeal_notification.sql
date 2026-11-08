-- PRISMA v2: preserve the live participant appeal notification side effect.

create or replace function public.participant_create_appeal(
 p_punishment_id uuid,
 p_reason text
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 uid uuid;
 punishment_id uuid := p_punishment_id;
 punishment public.moderation_logs%rowtype;
 appeal_id uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into uid from public.users u where u.auth_user_id=actor_uid and u.deleted_at is null limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;

 if not exists(
  select 1 from public.applications a
  where a.user_id=uid and a.status='ACCEPTED' and not a.is_archived
 ) then raise exception 'PLAYER_ACCESS_REQUIRED'; end if;

 if p_reason is null or char_length(trim(p_reason)) not between 10 and 2000 then
  raise exception 'INVALID_REASON';
 end if;

 if punishment_id is null then
  select m.id into punishment_id
  from public.moderation_logs m
  where m.target_id=uid and m.revoked=false and upper(coalesce(m.status,''))='ACTIVE'
    and m.type in ('WARN','MUTE','BAN','KICK')
  order by m.created_at desc,m.id desc
  limit 1;
 end if;
 if punishment_id is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

 select * into punishment
 from public.moderation_logs m
 where m.id=punishment_id and m.target_id=uid
 for update;
 if punishment.id is null then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
 if punishment.revoked or upper(coalesce(punishment.status,''))<>'ACTIVE' then raise exception 'PUNISHMENT_NOT_ACTIVE'; end if;

 if exists(
  select 1 from public.punishment_appeals pa
  where pa.user_id=uid and pa.punishment_id=punishment.id and pa.status in ('OPEN','IN_REVIEW')
 ) then raise exception 'APPEAL_ALREADY_EXISTS'; end if;

 insert into public.punishment_appeals(user_id,telegram_id,punishment_id,reason,status)
 values(uid,(select telegram_id from public.users where id=uid),punishment.id,trim(p_reason),'OPEN')
 returning id into appeal_id;

 insert into public.notifications(
  user_id,telegram_id,channel,kind,title,body,data,status,attempts
 ) values(
  uid,(select telegram_id from public.users where id=uid),'telegram','appeal_created',
  'Апелляция отправлена',
  'Ваша апелляция отправлена администрации.',
  jsonb_build_object('appeal_id',appeal_id,'punishment_id',punishment.id),
  'pending',0
 );

 return json_build_object('success',true,'appeal_id',appeal_id,'punishment_id',punishment.id);
end;
$function$;

revoke all on function public.participant_create_appeal(uuid,text) from public,anon;
grant execute on function public.participant_create_appeal(uuid,text) to authenticated;
