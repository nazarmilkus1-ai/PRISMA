-- PRISMA v2: staff dashboard overview, audit and notification read gateways.

create or replace function public.staff_get_dashboard_overview()
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='application.view' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return json_build_object(
  'pending_applications',(select count(*) from public.applications where status='PENDING' and not is_archived),
  'open_reports',(select count(*) from public.reports where status='OPEN'),
  'accepted_players',(select count(*) from public.users where status='ACCEPTED' and not is_banned and deleted_at is null),
  'active_clans',(select count(*) from public.clans where status='active' and deleted_at is null),
  'server',(select coalesce(row_to_json(s),'{}') from (
    select status,online_players,max_players,version,last_heartbeat_at from public.server_nodes where node_id='primary' limit 1
  ) s)
 );
end;
$function$;
revoke all on function public.staff_get_dashboard_overview() from public,anon;
grant execute on function public.staff_get_dashboard_overview() to authenticated;

create or replace function public.staff_get_audit_logs(p_limit integer default 300)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,300),1000));
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='admin.view_audit' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return coalesce((
  select json_agg(x order by created_sort desc) from (
   select json_build_object(
    'id',l.id,'actor_user_id',l.actor_user_id,'actor_tg_id',l.actor_tg_id,'action',l.action,'target_type',l.target_type,'target_id',l.target_id,
    'old_data',l.old_data,'new_data',l.new_data,'created_at',l.created_at,
    'actor',case when u.id is null then null else json_build_object('telegram_id',u.telegram_id,'telegram_username',u.telegram_username,'minecraft_nickname',u.minecraft_nickname,'full_name',u.full_name) end
   ) x,l.created_at created_sort
   from public.audit_logs l left join public.users u on u.id=l.actor_user_id
   order by l.created_at desc limit lim
  ) q
 ),'[]'::json);
end;
$function$;
revoke all on function public.staff_get_audit_logs(integer) from public,anon;
grant execute on function public.staff_get_audit_logs(integer) to authenticated;

create or replace function public.staff_list_notifications(p_limit integer default 200)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,200),500));
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='admin.view_audit' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return coalesce((
  select json_agg(json_build_object(
   'id',n.id,'telegram_id',n.telegram_id,'channel',n.channel,'kind',n.kind,'title',n.title,'body',n.body,'data',n.data,
   'status',n.status,'attempts',n.attempts,'last_error',n.last_error,'created_at',n.created_at,'sent_at',n.sent_at,'updated_at',n.updated_at
  ) order by n.created_at desc) from public.notifications n limit lim
 ),'[]'::json);
end;
$function$;
revoke all on function public.staff_list_notifications(integer) from public,anon;
grant execute on function public.staff_list_notifications(integer) to authenticated;
