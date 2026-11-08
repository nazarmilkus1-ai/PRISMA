-- PRISMA v2: appeal decisions are delivered through the central notification queue.
-- The staff RPC already writes audit + sync + notification atomically.

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
 notification_title text;
 notification_body text;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 if not exists(
   select 1 from public.admins a
   join public.role_permissions rp on rp.role_id=a.role_id
   join public.permissions p on p.id=rp.permission_id
   where a.user_id=actor.id and p.key='appeal.manage'
 ) then raise exception 'PERMISSION_DENIED'; end if;

 select * into appeal from public.punishment_appeals where id=p_appeal_id for update;
 if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

 if action='REVIEW' then new_status:='IN_REVIEW';
 elsif action='REJECT' then new_status:='REJECTED';
 elsif action='APPROVE' then new_status:='APPROVED';
 else raise exception 'UNKNOWN_ACTION'; end if;

 if p_note is not null and char_length(trim(p_note))>5000 then raise exception 'INVALID_NOTE'; end if;

 select * into target from public.users where id=appeal.user_id for update;
 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 if action='APPROVE' and appeal.punishment_id is not null then
   select * into punishment from public.moderation_logs where id=appeal.punishment_id for update;
   if punishment.id is not null and not punishment.revoked and punishment.type in ('WARN','MUTE','BAN') then
     revoke_result:=public.staff_revoke_moderation(punishment.id);
   elsif punishment.id is not null and not punishment.revoked and punishment.type='KICK' then
     select exists(select 1 from public.applications a where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived) into accepted;
     update public.users set is_whitelisted=case when accepted and not is_banned then true else is_whitelisted end,updated_at=now() where id=target.id;
     insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
     values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNREGISTER_KICK','appeal_id',appeal.id));
   end if;
 end if;

 update public.punishment_appeals
 set status=new_status,reviewed_by_tg_id=actor.telegram_id,
     review_note=case when p_note is null then review_note else trim(p_note) end,updated_at=now()
 where id=appeal.id;

 if action='APPROVE' then
   notification_title:='Апелляция одобрена';
   notification_body:='Ваша апелляция одобрена. Наказание снято, если оно было активным.';
 elsif action='REJECT' then
   notification_title:='Апелляция отклонена';
   notification_body:='Ваша апелляция отклонена.';
 else
   notification_title:='Апелляция взята в работу';
   notification_body:='Ваша апелляция взята администрацией в работу.';
 end if;

 insert into public.notifications(
   user_id,telegram_id,channel,kind,title,body,data,status,attempts
 ) values(
   target.id,target.telegram_id,'telegram','appeal_status',notification_title,
   notification_body||case when p_note is null or trim(p_note)='' then '' else E'\n\nКомментарий: '||trim(p_note) end,
   jsonb_build_object('appeal_id',appeal.id,'status',new_status,'punishment_id',appeal.punishment_id),
   'pending',0
 );

 insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
 values(
   actor.id,actor.telegram_id,'appeal.'||lower(action),'punishment_appeal',appeal.id,
   jsonb_build_object('status',appeal.status),
   jsonb_build_object('status',new_status,'note',p_note,'punishment_id',appeal.punishment_id)
 );

 return json_build_object(
   'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,'telegram_id',appeal.telegram_id,
   'punishment_id',appeal.punishment_id,'old_status',appeal.status,'status',new_status,
   'action',action,'revoke_result',revoke_result,'reviewed_by_tg_id',actor.telegram_id
 );
end;
$function$;

revoke all on function public.staff_manage_appeal(uuid,text,text) from public,anon;
grant execute on function public.staff_manage_appeal(uuid,text,text) to authenticated;
