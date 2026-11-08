create or replace function public.bot_set_staff_rank(
  p_actor_tg_id bigint,
  p_target_tg_id bigint,
  p_rank integer
)
returns json language plpgsql security definer set search_path=public as $$
declare
 actor_uid uuid; target_uid uuid; actor_priority integer; desired_role uuid;
 desired_priority integer; current_priority integer; role_name text;
begin
 if p_rank<1 or p_rank>5 then raise exception 'INVALID_STAFF_RANK'; end if;
 if p_actor_tg_id=p_target_tg_id then raise exception 'SELF_STAFF_ASSIGNMENT'; end if;
 select id into actor_uid from public.users where telegram_id=p_actor_tg_id and deleted_at is null limit 1;
 select id into target_uid from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor_uid and p.key='admin.manage') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
 if actor_priority is null then raise exception 'ADMIN_NOT_FOUND'; end if;
 desired_role:=case p_rank
  when 1 then (select id from public.roles where name='helper' limit 1)
  when 2 then (select id from public.roles where name='moderator' limit 1)
  when 3 then (select id from public.roles where name='admin' limit 1)
  when 4 then (select id from public.roles where name='head_admin' limit 1)
  when 5 then (select id from public.roles where name='owner' limit 1)
 end;
 select priority,name into desired_priority,role_name from public.roles where id=desired_role;
 if desired_role is null then raise exception 'STAFF_ROLE_NOT_FOUND'; end if;
 if actor_priority<=desired_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 select coalesce(r.priority,0) into current_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target_uid limit 1;
 if current_priority is not null and actor_priority<=current_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 insert into public.admins(user_id,role_id) values(target_uid,desired_role)
 on conflict(user_id) do update set role_id=excluded.role_id;
 return json_build_object('success',true,'rank',p_rank,'role',role_name,'target_id',target_uid);
end $$;

create or replace function public.bot_remove_staff(p_actor_tg_id bigint,p_target_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare actor_uid uuid; target_uid uuid; actor_priority integer; target_priority integer;
begin
 select id into actor_uid from public.users where telegram_id=p_actor_tg_id and deleted_at is null limit 1;
 select id into target_uid from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if actor_uid=target_uid then raise exception 'SELF_STAFF_ASSIGNMENT'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor_uid and p.key='admin.manage') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
 select r.priority into target_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target_uid limit 1;
 if target_priority is null then raise exception 'TARGET_NOT_STAFF'; end if;
 if actor_priority<=target_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 delete from public.admins where user_id=target_uid;
 return json_build_object('success',true,'target_id',target_uid);
end $$;

create or replace function public.bot_list_staff()
returns json language sql stable security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.priority desc,x.full_name),'[]'::json)
 from (
  select u.telegram_id as tg_id,u.full_name,u.telegram_username,r.name as role,r.priority,
    case r.name when 'helper' then 1 when 'moderator' then 2 when 'admin' then 3 when 'head_admin' then 4 when 'owner' then 5 else 0 end as rank
  from public.admins a join public.users u on u.id=a.user_id join public.roles r on r.id=a.role_id
  where u.deleted_at is null
 ) x;
$$;

revoke execute on function public.bot_set_staff_rank(bigint,bigint,integer) from public,anon,authenticated;
revoke execute on function public.bot_remove_staff(bigint,bigint) from public,anon,authenticated;
revoke execute on function public.bot_list_staff() from public,anon,authenticated;
grant execute on function public.bot_set_staff_rank(bigint,bigint,integer) to service_role;
grant execute on function public.bot_remove_staff(bigint,bigint) to service_role;
grant execute on function public.bot_list_staff() to service_role;
