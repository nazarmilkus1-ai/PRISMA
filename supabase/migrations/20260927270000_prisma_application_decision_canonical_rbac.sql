-- PRISMA v2: application decisions use canonical recursive RBAC
-- and return recipient metadata for all trusted clients.

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

   insert into public.application_history(
     application_id,action,actor_tg_id,reason
   )
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

   insert into public.application_history(
     application_id,action,actor_tg_id,reason
   )
   values(aid,'REJECTED',actor_tg_id,v_reason);
 end if;

 return json_build_object(
  'success',true,
  'application_id',aid,
  'user_id',uid,
  'status',new_status,
  'actor_user_id',p_actor_user_id,
  'actor_tg_id',actor_tg_id,
  'cooldown_until',cooldown,
  'target_telegram_id',(select telegram_id from public.users where id=uid),
  'application_no',(select application_no from public.applications where id=aid),
  'nickname',(select nickname from public.applications where id=aid)
 );
end;
$function$;
