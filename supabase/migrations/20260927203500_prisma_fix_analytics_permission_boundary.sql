-- PRISMA v2: analytics gateway must enforce the permission used by its
-- panel route, not the unrelated application.view permission.

create or replace function public.staff_get_analytics(
 p_days integer default 30,
 p_chat_days integer default 2
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 actor_id uuid;
 days_limit integer := greatest(1,least(coalesce(p_days,30),90));
 chat_limit integer := greatest(1,least(coalesce(p_chat_days,2),14));
 apps json;
 chats json;
 ratings json;
 audits json;
 admins json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

 select u.id into actor_id
 from public.users u
 join public.admins a on a.user_id=u.id
 join public.role_permissions rp on rp.role_id=a.role_id
 join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid
   and u.deleted_at is null
   and p.key='analytics.view'
 limit 1;

 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at),'[]'::json) into apps
 from (
   select created_at,status
   from public.applications
   where created_at>=now()-make_interval(days=>days_limit)
     and not is_archived
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at),'[]'::json) into chats
 from (
   select user_id,created_at
   from public.chat_logs
   where created_at>=now()-make_interval(days=>chat_limit)
 ) x;

 select coalesce(json_agg(to_jsonb(x)),'[]'::json) into ratings
 from (
   select pr.value
   from public.poll_ratings pr
   join public.polls p on p.id=pr.poll_id
   where p.kind='SERVER_RATING' and p.is_active=true
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into audits
 from (
   select actor_tg_id,action,created_at
   from public.audit_logs
   where created_at>=now()-make_interval(days=>days_limit)
   order by created_at desc
   limit 5000
 ) x;

 select coalesce(json_agg(x),'[]'::json) into admins
 from (
   select json_build_object(
     'telegram_id',u.telegram_id,
     'telegram_username',u.telegram_username,
     'minecraft_nickname',u.minecraft_nickname,
     'full_name',u.full_name,
     'role',r.name
   ) x
   from public.admins a
   join public.users u on u.id=a.user_id and u.deleted_at is null
   join public.roles r on r.id=a.role_id
 ) x;

 return json_build_object(
  'applications',apps,
  'chat',chats,
  'ratings',ratings,
  'audit',audits,
  'admins',admins
 );
end;
$function$;

revoke all on function public.staff_get_analytics(integer,integer) from public,anon;
grant execute on function public.staff_get_analytics(integer,integer) to authenticated;
