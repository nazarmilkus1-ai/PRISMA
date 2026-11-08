-- PRISMA v2: dedicated least-privilege permissions for dashboard and analytics.

insert into public.permissions(key,description)
values
 ('dashboard.view','Просмотр главного дашборда'),
 ('analytics.view','Просмотр аналитики')
on conflict (key) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key in ('dashboard.view','analytics.view')
where r.name in ('owner','head_admin','admin','moderator')
on conflict do nothing;

create or replace function public.staff_get_dashboard_overview()
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id
 from public.users u
 join public.admins a on a.user_id=u.id
 join public.role_permissions rp on rp.role_id=a.role_id
 join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='dashboard.view'
 limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return json_build_object(
  'pending_applications',(select count(*) from public.applications where status='PENDING' and not is_archived),
  'open_reports',(select count(*) from public.reports where status='OPEN'),
  'accepted_players',(select count(*) from public.users where status='ACCEPTED' and not is_banned and deleted_at is null),
  'active_clans',(select count(*) from public.clans where status='active' and deleted_at is null),
  'server',(select coalesce(row_to_json(s),'{}') from (
    select status,online_players,max_players,version,last_heartbeat_at
    from public.server_nodes where node_id='primary' limit 1
  ) s)
 );
end;
$function$;

create or replace function public.staff_get_analytics(
 p_days integer default 30,
 p_chat_days integer default 2
)
returns json language plpgsql security definer set search_path=''
as $function$
declare
 actor_uid uuid:=(select auth.uid()); actor_id uuid;
 days_limit integer:=greatest(1,least(coalesce(p_days,30),90));
 chat_limit integer:=greatest(1,least(coalesce(p_chat_days,2),14));
 apps json; chats json; ratings json; audits json; admins json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id
 from public.users u
 join public.admins a on a.user_id=u.id
 join public.role_permissions rp on rp.role_id=a.role_id
 join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='analytics.view'
 limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at),'[]'::json) into apps
 from (
  select created_at,status from public.applications
  where created_at>=now()-make_interval(days=>days_limit) and not is_archived
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at),'[]'::json) into chats
 from (
  select user_id,created_at from public.chat_logs
  where created_at>=now()-make_interval(days=>chat_limit)
 ) x;

 select coalesce(json_agg(to_jsonb(x)),'[]'::json) into ratings
 from (
  select pr.value
  from public.poll_ratings pr join public.polls p on p.id=pr.poll_id
  where p.kind='SERVER_RATING' and p.is_active=true
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into audits
 from (
  select actor_tg_id,action,created_at
  from public.audit_logs
  where created_at>=now()-make_interval(days=>days_limit)
  order by created_at desc limit 5000
 ) x;

 select coalesce(json_agg(x),'[]'::json) into admins
 from (
  select json_build_object(
   'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,
   'minecraft_nickname',u.minecraft_nickname,'full_name',u.full_name,'role',r.name
  ) x
  from public.admins a
  join public.users u on u.id=a.user_id and u.deleted_at is null
  join public.roles r on r.id=a.role_id
 ) x;

 return json_build_object('applications',apps,'chat',chats,'ratings',ratings,'audit',audits,'admins',admins);
end;
$function$;

create or replace function public.staff_get_monitoring()
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; metrics_data json; events_data json; chat_data json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id
 from public.users u
 join public.admins a on a.user_id=u.id
 join public.role_permissions rp on rp.role_id=a.role_id
 join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='system.health'
 limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

 select coalesce(json_agg(to_jsonb(x) order by x.recorded_at desc),'[]'::json)
 into metrics_data
 from (
  select id,server_name,online_players,max_players,tps,cpu_percent,memory_used_mb,memory_max_mb,
         uptime_seconds,version,world,recorded_at
  from public.server_metrics order by recorded_at desc limit 120
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
 into events_data
 from (
  select id,event_type,nickname,command,message,world,created_at,user_id
  from public.minecraft_events order by created_at desc limit 60
 ) x;

 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
 into chat_data
 from (
  select id,user_id,message,world,created_at
  from public.chat_logs order by created_at desc limit 30
 ) x;

 return json_build_object('metrics',metrics_data,'events',events_data,'chat_logs',chat_data);
end;
$function$;
