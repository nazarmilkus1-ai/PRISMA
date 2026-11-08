-- PRISMA v2: route appeal notifications through the central notification queue.
-- Staff alerts and player status changes are generated inside the domain layer;
-- panel/bot clients only acknowledge the RPC result.

create or replace function private.enqueue_staff_appeal_notification(
 p_appeal_id uuid,
 p_player_tg_id bigint,
 p_punishment_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
begin
  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,attempts
  )
  select
    u.id,u.telegram_id,'telegram','MODERATION',
    'Новая апелляция',
    'Игрок подал апелляцию на наказание.',
    jsonb_build_object(
      'appeal_id',p_appeal_id,
      'player_telegram_id',p_player_tg_id,
      'punishment_id',p_punishment_id
    ),
    'pending',0
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.deleted_at is null
    and u.telegram_id is not null
    and p.key='appeal.view';
end;
$function$;

revoke all on function private.enqueue_staff_appeal_notification(uuid,bigint,uuid)
from public,anon,authenticated;

create or replace function private.enqueue_appeal_status_notification(
 p_appeal_id uuid,
 p_user_id uuid,
 p_status text,
 p_note text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  title text;
  body text;
begin
  title:=case p_status
    when 'APPROVED' then 'Апелляция одобрена'
    when 'REJECTED' then 'Апелляция отклонена'
    when 'IN_REVIEW' then 'Апелляция взята в работу'
    else 'Статус апелляции изменён'
  end;

  body:=case p_status
    when 'APPROVED' then 'Ваша апелляция одобрена. Наказание снято, если оно было активным.'
    when 'REJECTED' then 'Ваша апелляция отклонена.'
    when 'IN_REVIEW' then 'Ваша апелляция взята администрацией в работу.'
    else 'Статус вашей апелляции изменён.'
  end;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,attempts
  )
  select
    u.id,u.telegram_id,'telegram','MODERATION',title,
    body ||
      case
        when p_note is not null and trim(p_note)<>''
          then E'\n\nКомментарий: '||trim(p_note)
        else ''
      end,
    jsonb_build_object(
      'appeal_id',p_appeal_id,
      'status',p_status,
      'note',p_note
    ),
    'pending',0
  from public.users u
  where u.id=p_user_id
    and u.deleted_at is null
    and u.telegram_id is not null;
end;
$function$;

revoke all on function private.enqueue_appeal_status_notification(uuid,uuid,text,text)
from public,anon,authenticated;

-- Re-apply the participant and staff appeal flows against the shared helpers.

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
 player_tg_id bigint;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id,u.telegram_id into uid,player_tg_id
 from public.users u
 where u.auth_user_id=actor_uid and u.deleted_at is null
 limit 1;
 if uid is null then raise exception 'USER_NOT_FOUND'; end if;

 if not exists(
   select 1
   from public.applications a
   where a.user_id=uid and a.status='ACCEPTED' and not a.is_archived
 ) then
   raise exception 'PLAYER_ACCESS_REQUIRED';
 end if;

 if p_reason is null or char_length(trim(p_reason)) not between 10 and 2000 then
   raise exception 'INVALID_REASON';
 end if;

 if punishment_id is null then
   select m.id into punishment_id
   from public.moderation_logs m
   where m.target_id=uid
     and m.revoked=false
     and upper(coalesce(m.status,''))='ACTIVE'
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
 if punishment.revoked or upper(coalesce(punishment.status,''))<>'ACTIVE' then
   raise exception 'PUNISHMENT_NOT_ACTIVE';
 end if;

 if exists(
   select 1
   from public.punishment_appeals pa
   where pa.user_id=uid
     and pa.punishment_id=punishment.id
     and pa.status in ('OPEN','IN_REVIEW')
 ) then
   raise exception 'APPEAL_ALREADY_EXISTS';
 end if;

 insert into public.punishment_appeals(
   user_id,telegram_id,punishment_id,reason,status
 )
 values(uid,player_tg_id,punishment.id,trim(p_reason),'OPEN')
 returning id into appeal_id;

 insert into public.notifications(
   user_id,telegram_id,channel,kind,title,body,data,status,attempts
 )
 values(
   uid,player_tg_id,'telegram','appeal_created',
   'Апелляция отправлена',
   'Ваша апелляция отправлена администрации.',
   jsonb_build_object(
     'appeal_id',appeal_id,
     'punishment_id',punishment.id
   ),
   'pending',0
 );

 perform private.enqueue_staff_appeal_notification(
   appeal_id,player_tg_id,punishment.id
 );

 return json_build_object(
   'success',true,
   'appeal_id',appeal_id,
   'punishment_id',punishment.id
 );
end;
$function$;

revoke all on function public.participant_create_appeal(uuid,text)
from public,anon;

grant execute on function public.participant_create_appeal(uuid,text)
to authenticated;

create or replace function public.staff_manage_appeal(
 p_appeal_id uuid,
 p_action text,
 p_note text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 actor public.users%rowtype;
 target public.users%rowtype;
 appeal public.punishment_appeals%rowtype;
 punishment public.moderation_logs%rowtype;
 action text := upper(trim(p_action));
 new_status text;
 revoke_result json;
 accepted boolean := false;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

 select * into actor
 from public.users
 where auth_user_id=actor_uid and deleted_at is null
 limit 1;

 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

 if not exists(
   select 1
   from public.admins a
   join public.role_permissions rp on rp.role_id=a.role_id
   join public.permissions p on p.id=rp.permission_id
   where a.user_id=actor.id and p.key='appeal.manage'
 ) then
   raise exception 'PERMISSION_DENIED';
 end if;

 if action='REVIEW' then
   new_status:='IN_REVIEW';
 elsif action='REJECT' then
   new_status:='REJECTED';
 elsif action='APPROVE' then
   new_status:='APPROVED';
 else
   raise exception 'UNKNOWN_ACTION';
 end if;

 if p_note is not null and char_length(trim(p_note))>5000 then
   raise exception 'INVALID_NOTE';
 end if;

 select * into appeal
 from public.punishment_appeals
 where id=p_appeal_id
 for update;

 if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 if appeal.status not in ('OPEN','IN_REVIEW') then
   raise exception 'APPEAL_ALREADY_CLOSED';
 end if;

 select * into target
 from public.users
 where id=appeal.user_id
 for update;

 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 if action='APPROVE' and appeal.punishment_id is not null then
   select * into punishment
   from public.moderation_logs
   where id=appeal.punishment_id
   for update;

   if punishment.id is not null
      and not punishment.revoked
      and punishment.type in ('WARN','MUTE','BAN') then
     revoke_result:=public.staff_revoke_moderation(punishment.id);

   elsif punishment.id is not null
     and not punishment.revoked
     and punishment.type='KICK' then

     select exists(
       select 1
       from public.applications a
       where a.user_id=target.id
         and a.status='ACCEPTED'
         and not a.is_archived
     ) into accepted;

     update public.users
     set is_whitelisted=case
       when accepted and not is_banned then true
       else is_whitelisted
     end,
     updated_at=now()
     where id=target.id;

     insert into public.sync_outbox(
       aggregate_type,aggregate_id,event_type,payload
     )
     values(
       'user',target.id,'user.moderation.updated',
       jsonb_build_object(
         'type','UNREGISTER_KICK',
         'appeal_id',appeal.id
       )
     );
   end if;
 end if;

 update public.punishment_appeals
 set status=new_status,
     reviewed_by_tg_id=actor.telegram_id,
     review_note=case
       when p_note is null then review_note
       else trim(p_note)
     end,
     updated_at=now()
 where id=appeal.id;

 perform private.enqueue_appeal_status_notification(
   appeal.id,appeal.user_id,new_status,p_note
 );

 insert into public.audit_logs(
   actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
 )
 values(
   actor.id,actor.telegram_id,'appeal.'||lower(action),
   'punishment_appeal',appeal.id,
   jsonb_build_object('status',appeal.status),
   jsonb_build_object(
     'status',new_status,
     'note',p_note,
     'punishment_id',appeal.punishment_id
   )
 );

 return json_build_object(
   'success',true,
   'appeal_id',appeal.id,
   'user_id',appeal.user_id,
   'telegram_id',appeal.telegram_id,
   'punishment_id',appeal.punishment_id,
   'old_status',appeal.status,
   'status',new_status,
   'action',action,
   'revoke_result',revoke_result,
   'reviewed_by_tg_id',actor.telegram_id
 );
end;
$function$;

revoke all on function public.staff_manage_appeal(uuid,text,text)
from public,anon;

grant execute on function public.staff_manage_appeal(uuid,text,text)
to authenticated;

create or replace function public.bot_create_appeal(
 p_tg_id bigint,
 p_reason text,
 p_punishment_id uuid default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 uid uuid;
 target_punishment uuid;
 punishment_status text;
 punishment_revoked boolean;
 appeal_id uuid;
begin
 if p_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
 if p_reason is null or char_length(trim(p_reason)) not between 10 and 2000 then raise exception 'INVALID_REASON'; end if;

 select u.id into uid
 from public.users u
 where u.telegram_id=p_tg_id and u.deleted_at is null
 limit 1;

 if uid is null then raise exception 'USER_NOT_FOUND'; end if;

 if p_punishment_id is null then
   select m.id into target_punishment
   from public.moderation_logs m
   where m.target_id=uid
     and m.revoked=false
     and upper(coalesce(m.status,''))='ACTIVE'
     and m.type not in ('UNMUTE','UNWARN','UNBAN','WHITELIST','UNWHITELIST')
   order by m.created_at desc,m.id desc
   limit 1;
 else
   select m.id,upper(coalesce(m.status,'')),coalesce(m.revoked,false)
   into target_punishment,punishment_status,punishment_revoked
   from public.moderation_logs m
   where m.id=p_punishment_id and m.target_id=uid
   for update;

   if target_punishment is null then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
   if punishment_revoked or punishment_status<>'ACTIVE' then
     raise exception 'PUNISHMENT_NOT_ACTIVE';
   end if;
 end if;

 if target_punishment is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

 if exists(
   select 1
   from public.punishment_appeals pa
   where pa.user_id=uid
     and pa.punishment_id=target_punishment
     and pa.status in ('OPEN','IN_REVIEW')
 ) then
   raise exception 'APPEAL_ALREADY_EXISTS';
 end if;

 insert into public.punishment_appeals(
   user_id,telegram_id,punishment_id,reason,status
 )
 values(uid,p_tg_id,target_punishment,trim(p_reason),'OPEN')
 returning id into appeal_id;

 perform private.enqueue_staff_appeal_notification(
   appeal_id,p_tg_id,target_punishment
 );

 return json_build_object(
   'success',true,
   'appeal_id',appeal_id,
   'punishment_id',target_punishment
 );
end;
$function$;

revoke all on function public.bot_create_appeal(bigint,text,uuid)
from public,anon,authenticated;

grant execute on function public.bot_create_appeal(bigint,text,uuid)
to service_role;

create or replace function public.bot_manage_appeal(
 p_appeal_id uuid,
 p_action text,
 p_admin_tg_id bigint,
 p_note text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 admin_uid uuid;
 target public.users%rowtype;
 appeal public.punishment_appeals%rowtype;
 punishment public.moderation_logs%rowtype;
 action text := upper(trim(p_action));
 new_status text;
 accepted boolean := false;
 punishment_action_id uuid;
 was_lifted boolean := false;
begin
 if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;

 select a.user_id into admin_uid
 from public.admins a
 join public.users u on u.id=a.user_id
 where u.telegram_id=p_admin_tg_id and u.deleted_at is null
 limit 1;

 if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;

 if not public.bot_check_admin_permission(
   p_admin_tg_id,'appeal.manage'
 ) then
   raise exception 'PERMISSION_DENIED';
 end if;

 if action='REVIEW' then new_status:='IN_REVIEW';
 elsif action='REJECT' then new_status:='REJECTED';
 elsif action='APPROVE' then new_status:='APPROVED';
 else raise exception 'UNKNOWN_ACTION'; end if;

 if p_note is not null and char_length(trim(p_note))>5000 then
   raise exception 'INVALID_NOTE';
 end if;

 select * into appeal
 from public.punishment_appeals
 where id=p_appeal_id
 for update;

 if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

 select * into target
 from public.users
 where id=appeal.user_id
 for update;

 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 if action='APPROVE' and appeal.punishment_id is not null then
   select * into punishment
   from public.moderation_logs
   where id=appeal.punishment_id
   for update;

   if punishment.id is not null and not punishment.revoked then
     if punishment.type='WARN' then
       update public.users
       set warning_count=greatest(0,warning_count-1),updated_at=now()
       where id=target.id;

       update public.moderation_logs
       set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,
           status='REVOKED',applied_at=coalesce(applied_at,now())
       where id=punishment.id;

       insert into public.moderation_logs(
         target_id,issued_by_tg_id,type,reason,source,status,applied_at,revoked
       )
       values(
         target.id,p_admin_tg_id,'UNWARN','Покарання знято апеляцією',
         'BOT','REVOKED',now(),true
       )
       returning id into punishment_action_id;

       was_lifted:=true;

     elsif punishment.type='MUTE' then
       update public.users
       set is_muted=false,muted_until=null,updated_at=now()
       where id=target.id;

       update public.moderation_logs
       set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,
           status='REVOKED',applied_at=coalesce(applied_at,now())
       where id=punishment.id;

       insert into public.moderation_logs(
         target_id,issued_by_tg_id,type,reason,source,status,applied_at,revoked
       )
       values(
         target.id,p_admin_tg_id,'UNMUTE','Покарання знято апеляцією',
         'BOT','REVOKED',now(),true
       )
       returning id into punishment_action_id;

       was_lifted:=true;

     elsif punishment.type='BAN' then
       select exists(
         select 1
         from public.applications a
         where a.user_id=target.id
           and a.status='ACCEPTED'
           and not a.is_archived
       ) into accepted;

       update public.users
       set is_banned=false,banned_until=null,
           ban_reason=null,ban_type=null,
           is_whitelisted=case when accepted then true else is_whitelisted end,
           updated_at=now()
       where id=target.id;

       update public.moderation_logs
       set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,
           status='REVOKED',applied_at=coalesce(applied_at,now())
       where id=punishment.id;

       insert into public.moderation_logs(
         target_id,issued_by_tg_id,type,reason,source,status,applied_at,revoked
       )
       values(
         target.id,p_admin_tg_id,'UNBAN','Покарання знято апеляцією',
         'BOT','REVOKED',now(),true
       )
       returning id into punishment_action_id;

       was_lifted:=true;

     elsif punishment.type='KICK' then
       select exists(
         select 1
         from public.applications a
         where a.user_id=target.id
           and a.status='ACCEPTED'
           and not a.is_archived
       ) into accepted;

       update public.users
       set is_whitelisted=case
         when accepted and not is_banned then true
         else is_whitelisted
       end,
       updated_at=now()
       where id=target.id;

       insert into public.sync_outbox(
         aggregate_type,aggregate_id,event_type,payload
       )
       values(
         'user',target.id,'user.moderation.updated',
         jsonb_build_object(
           'type','UNREGISTER_KICK',
           'appeal_id',appeal.id
         )
       );

       was_lifted:=true;
     end if;
   end if;
 end if;

 perform private.prisma_recompute_player_rating(target.id);

 update public.punishment_appeals
 set status=new_status,
     reviewed_by_tg_id=p_admin_tg_id,
     review_note=case
       when p_note is null then review_note
       else trim(p_note)
     end,
     updated_at=now()
 where id=appeal.id;

 perform private.enqueue_appeal_status_notification(
   appeal.id,appeal.user_id,new_status,p_note
 );

 insert into public.audit_logs(
   actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
 )
 values(
   admin_uid,p_admin_tg_id,'appeal.'||lower(action),
   'punishment_appeal',appeal.id,
   jsonb_build_object('status',appeal.status),
   jsonb_build_object(
     'status',new_status,'note',p_note,
     'punishment_id',appeal.punishment_id,
     'was_lifted',was_lifted,
     'punishment_action_id',punishment_action_id
   )
 );

 return json_build_object(
   'success',true,
   'appeal_id',appeal.id,
   'user_id',appeal.user_id,
   'telegram_id',appeal.telegram_id,
   'punishment_id',appeal.punishment_id,
   'old_status',appeal.status,
   'status',new_status,
   'action',action,
   'was_lifted',was_lifted,
   'punishment_action_id',punishment_action_id
 );
end;
$function$;

revoke all on function public.bot_manage_appeal(uuid,text,bigint,text)
from public,anon,authenticated;

grant execute on function public.bot_manage_appeal(uuid,text,bigint,text)
to service_role;
