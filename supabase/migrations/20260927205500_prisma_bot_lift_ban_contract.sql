-- PRISMA v2: trusted bot punishment lifting contract.
-- /unban uses the same service-role adapter as /unmute and /unwarn.

create or replace function public.bot_lift_punishment(
 p_user_tg_id bigint,
 p_type text,
 p_admin_tg_id bigint
)
returns json
language plpgsql
security definer
set search_path='public'
as $function$
declare
 uid uuid;
 admin_uid uuid;
 pid uuid;
 new_id uuid;
 typ text:=upper(trim(p_type));
 accepted boolean:=false;
 action_type text;
begin
 select id into uid
 from public.users
 where telegram_id=p_user_tg_id and deleted_at is null
 for update;

 select a.user_id into admin_uid
 from public.admins a
 join public.users u on u.id=a.user_id
 where u.telegram_id=p_admin_tg_id and u.deleted_at is null
 limit 1;

 if uid is null or admin_uid is null then
   raise exception 'USER_OR_ADMIN_NOT_FOUND';
 end if;

 if typ not in ('WARN','MUTE','BAN') then
   raise exception 'UNSUPPORTED_LIFT_TYPE';
 end if;

 if not private.prisma_has_user_permission(admin_uid,'punishment.remove') then
   raise exception 'ADMIN_LACKS_PERMISSION';
 end if;

 select m.id into pid
 from public.moderation_logs m
 where m.target_id=uid
   and m.type=typ
   and m.status='ACTIVE'
   and m.revoked=false
   and (m.expires_at is null or m.expires_at>now())
 order by m.created_at desc
 limit 1
 for update;

 if pid is null then
   raise exception 'NO_ACTIVE_PUNISHMENT';
 end if;

 update public.moderation_logs
 set revoked=true,
     revoked_at=now(),
     revoked_by_tg_id=p_admin_tg_id,
     status='REVOKED',
     applied_at=coalesce(applied_at,now())
 where id=pid;

 if typ='MUTE' then
   update public.users
   set is_muted=false,muted_until=null,updated_at=now()
   where id=uid;
   action_type:='UNMUTE';
 elsif typ='WARN' then
   update public.users
   set warning_count=greatest(0,warning_count-1),updated_at=now()
   where id=uid;
   action_type:='UNWARN';
 else
   select exists(
     select 1
     from public.applications a
     where a.user_id=uid
       and a.status='ACCEPTED'
       and not a.is_archived
   ) into accepted;

   update public.users
   set is_banned=false,
       banned_until=null,
       ban_reason=null,
       ban_type=null,
       is_whitelisted=case
         when accepted then true
         else is_whitelisted
       end,
       updated_at=now()
   where id=uid;
   action_type:='UNBAN';
 end if;

 insert into public.moderation_logs(
   target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
 )
 values(
   uid,p_admin_tg_id,null,action_type,'Покарання знято','BOT','REVOKED',now(),true
 )
 returning id into new_id;

 insert into public.sync_outbox(
   aggregate_type,aggregate_id,event_type,payload
 )
 values(
   'user',uid,'user.moderation.updated',
   jsonb_build_object('punishment_id',pid,'type',action_type)
 );

 perform private.prisma_recompute_player_rating(uid);
 perform private.enqueue_moderation_notification(
   uid,action_type,'Покарання знято',null
 );

 return json_build_object(
   'success',true,
   'punishment_id',pid,
   'action_id',new_id,
   'type',typ,
   'action_type',action_type
 );
end;
$function$;

revoke all on function public.bot_lift_punishment(bigint,text,bigint)
from public,anon,authenticated;
grant execute on function public.bot_lift_punishment(bigint,text,bigint)
to service_role;
