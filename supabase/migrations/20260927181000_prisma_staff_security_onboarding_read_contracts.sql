-- PRISMA v2: staff read gateways for security center and onboarding.

create or replace function public.staff_get_security_snapshot(p_limit integer default 200)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,200),500)); events_data json; logins_data json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='admin.view_audit' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into events_data
 from (select id,event_type,telegram_id,ip_hash,user_agent,risk_score,payload,created_at from public.security_events order by created_at desc limit lim) x;
 select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json) into logins_data
 from (select id,user_id,telegram_id,method,success,ip_hash,user_agent,created_at from public.login_history order by created_at desc limit lim) x;
 return json_build_object('events',events_data,'logins',logins_data);
end;
$function$;
revoke all on function public.staff_get_security_snapshot(integer) from public,anon;
grant execute on function public.staff_get_security_snapshot(integer) to authenticated;

create or replace function public.staff_get_onboarding(p_limit integer default 1000)
returns json language plpgsql security definer set search_path=''
as $function$
declare actor_uid uuid:=(select auth.uid()); actor_id uuid; lim integer:=greatest(1,least(coalesce(p_limit,1000),2000));
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='player.view' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 return coalesce((
   select json_agg(to_jsonb(x) order by x.community_last_seen_at desc nulls last)
   from (
     select u.id,u.telegram_id,u.telegram_username,u.first_name,u.full_name,u.community_first_seen_at,u.community_last_seen_at,u.bot_started_at,u.created_at
     from public.users u
     where u.deleted_at is null
       and u.community_first_seen_at is not null
       and not exists (select 1 from public.applications a where a.user_id=u.id)
     order by u.community_last_seen_at desc nulls last
     limit lim
   ) x
 ),'[]'::json);
end;
$function$;
revoke all on function public.staff_get_onboarding(integer) from public,anon;
grant execute on function public.staff_get_onboarding(integer) to authenticated;
