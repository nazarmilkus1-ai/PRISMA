-- PRISMA v2: application decisions must reference a live participant.
-- Prevents soft-deleted users from being transitioned by a stale application.

create or replace function private.prisma_decide_application(
 p_application_id uuid,
 p_actor_user_id uuid,
 p_action text,
 p_reason text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 aid uuid;
 uid uuid;
 actor_tg_id bigint;
 actor_name text;
 normalized_action text:=lower(trim(p_action));
 v_reason text:=left(nullif(trim(p_reason),''),2000);
 new_status public.application_status;
 cooldown timestamptz;
 target_tg_id bigint;
 application_no bigint;
 nickname text;
begin
 if p_actor_user_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 if normalized_action not in ('approve','reject') then raise exception 'INVALID_ACTION'; end if;

 select a.id,a.user_id,a.application_no,a.nickname
 into aid,uid,application_no,nickname
 from public.applications a
 where a.id=p_application_id
   and a.status='PENDING'
   and not a.is_archived
 for update;

 if aid is null then raise exception 'APPLICATION_NOT_FOUND'; end if;

 if not exists(
   select 1 from public.users u
   where u.id=uid and u.deleted_at is null
 ) then
   raise exception 'USER_NOT_FOUND';
 end if;

 select u.telegram_id,
        coalesce(
          u.full_name,
          nullif(trim(concat_ws(' ',u.first_name,u.last_name)),''),
          u.telegram_username
        )
 into actor_tg_id,actor_name
 from public.users u
 where u.id=p_actor_user_id
   and u.deleted_at is null
 limit 1;

 if actor_tg_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;

 if not private.prisma_has_user_permission(
   p_actor_user_id,
   case when normalized_action='approve' then 'application.approve' else 'application.reject' end
 ) then
   raise exception 'ADMIN_LACKS_PERMISSION';
 end if;

 select u.telegram_id into target_tg_id
 from public.users u
 where u.id=uid;

 if normalized_action='approve' then
   new_status='ACCEPTED';
   cooldown=null;

   update public.applications
   set status=new_status,rejection_reason=null,reviewed_by_tg_id=actor_tg_id,
       reviewed_by_name=actor_name,reviewed_at=now(),cooldown_until=null,updated_at=now()
   where id=aid;

   update public.users
   set status='ACCEPTED',is_whitelisted=true,updated_at=now()
   where id=uid;

   insert into public.application_history(application_id,action,actor_tg_id,reason)
   values(aid,'APPROVED',actor_tg_id,null);

   perform private.enqueue_application_status_notification(
     aid,uid,'ACCEPTED',null,application_no
   );
 else
   new_status='REJECTED';
   cooldown=now()+interval '7 days';

   update public.applications
   set status=new_status,rejection_reason=v_reason,reviewed_by_tg_id=actor_tg_id,
       reviewed_by_name=actor_name,reviewed_at=now(),cooldown_until=cooldown,updated_at=now()
   where id=aid;

   update public.users
   set status='REJECTED',is_whitelisted=false,updated_at=now()
   where id=uid;

   insert into public.application_history(application_id,action,actor_tg_id,reason)
   values(aid,'REJECTED',actor_tg_id,v_reason);

   perform private.enqueue_application_status_notification(
     aid,uid,'REJECTED',v_reason,application_no
   );
 end if;

 insert into public.audit_logs(
   actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
 )
 values(
   p_actor_user_id,actor_tg_id,
   'application.'||case when normalized_action='approve' then 'approve' else 'reject' end,
   'application',aid,
   jsonb_build_object('status','PENDING'),
   jsonb_build_object(
     'status',new_status,
     'reason',v_reason,
     'application_no',application_no,
     'nickname',nickname
   )
 );

 return json_build_object(
   'success',true,'application_id',aid,'user_id',uid,'status',new_status,
   'actor_user_id',p_actor_user_id,'actor_tg_id',actor_tg_id,
   'cooldown_until',cooldown,'target_telegram_id',target_tg_id,
   'application_no',application_no,'nickname',nickname
 );
end;
$function$;
