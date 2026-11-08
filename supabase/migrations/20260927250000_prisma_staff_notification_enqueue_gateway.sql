-- PRISMA v2: panel notification enqueue gateway.
-- Server-side panel code must use the authenticated staff session rather than
-- mutating notifications through the service-role client.

insert into public.permissions(key,description)
values ('notification.send','Постановка Telegram-уведомлений в очередь')
on conflict (key) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key='notification.send'
where r.name in ('owner','head_admin','admin','moderator')
on conflict do nothing;

create or replace function public.staff_enqueue_notification(
 p_telegram_id bigint,
 p_user_id uuid default null,
 p_kind text default 'SYSTEM',
 p_title text default 'PRISMA',
 p_body text default '',
 p_data jsonb default '{}'::jsonb
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 actor_id uuid;
 notification_id uuid;
 target_user_id uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

 select u.id into actor_id
 from public.users u
 where u.auth_user_id=actor_uid
   and u.deleted_at is null
   and private.prisma_has_user_permission(u.id,'notification.send')
 limit 1;

 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

 if p_telegram_id is null or p_telegram_id=0 then
   raise exception 'INVALID_TELEGRAM_ID';
 end if;
 if p_body is null or char_length(trim(p_body))=0 then
   raise exception 'INVALID_NOTIFICATION';
 end if;
 if char_length(coalesce(p_title,''))>200 then
   raise exception 'INVALID_NOTIFICATION_TITLE';
 end if;
 if char_length(p_body)>4000 then
   raise exception 'INVALID_NOTIFICATION_BODY';
 end if;

 if p_user_id is not null then
   select u.id into target_user_id
   from public.users u
   where u.id=p_user_id
     and u.deleted_at is null
     and u.telegram_id=p_telegram_id
   limit 1;

   if target_user_id is null then
     raise exception 'TELEGRAM_USER_MISMATCH';
   end if;
 end if;

 insert into public.notifications(
   user_id,telegram_id,channel,kind,title,body,data,status,attempts
 )
 values(
   target_user_id,p_telegram_id,'telegram',
   upper(trim(coalesce(p_kind,'SYSTEM'))),
   left(coalesce(p_title,'PRISMA'),200),
   trim(p_body),
   coalesce(p_data,'{}'::jsonb),
   'pending',0
 )
 returning id into notification_id;

 return json_build_object(
   'success',true,
   'notification_id',notification_id,
   'status','pending'
 );
end;
$function$;

revoke all on function public.staff_enqueue_notification(bigint,uuid,text,text,text,jsonb)
from public,anon;

grant execute on function public.staff_enqueue_notification(bigint,uuid,text,text,text,jsonb)
to authenticated;
