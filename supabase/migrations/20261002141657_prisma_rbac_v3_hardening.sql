-- PRISMA v2: RBAC hierarchy hardening and canonical role projection.

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.key='admin.manage'
where r.name='head_admin'
on conflict do nothing;

create or replace function public.staff_manage_admin(p_action text,p_admin_id uuid default null,p_telegram_id bigint default null,p_role_name text default null)
returns json language plpgsql security definer set search_path='' as $function$
declare
 actor_uid uuid:=auth.uid(); actor public.users%rowtype; target public.admins%rowtype; target_user public.users%rowtype;
 role_row public.roles%rowtype; old_role text; target_priority int; actor_priority int; new_admin uuid; actor_role text;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 if not exists(
   select 1 from public.admins a
   join public.role_permissions rp on rp.role_id=a.role_id
   join public.permissions p on p.id=rp.permission_id
   where a.user_id=actor.id and p.key='admin.manage'
 ) then raise exception 'PERMISSION_DENIED'; end if;
 select r.priority,r.name into actor_priority,actor_role
 from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor.id limit 1;

 if upper(p_action)='CREATE' then
   if p_telegram_id is null or p_role_name is null then raise exception 'INVALID_INPUT'; end if;
   select * into role_row from public.roles where name=lower(trim(p_role_name)) limit 1;
   if role_row.id is null then raise exception 'ROLE_NOT_FOUND'; end if;
   if role_row.name='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   if actor_role='head_staff' and role_row.branch<>'moderation' then raise exception 'STAFF_BRANCH_FORBIDS'; end if;
   if role_row.priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   select * into target_user from public.users where telegram_id=p_telegram_id and deleted_at is null limit 1;
   if target_user.id is null then insert into public.users(telegram_id) values(p_telegram_id) returning * into target_user; end if;
   if exists(select 1 from public.admins where user_id=target_user.id) then raise exception 'ALREADY_ADMIN'; end if;
   insert into public.admins(user_id,role_id) values(target_user.id,role_row.id) returning id into new_admin;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
   values(actor.id,actor.telegram_id,'admin.create','admin',new_admin,jsonb_build_object('telegram_id',p_telegram_id,'role',role_row.name));
   return json_build_object('success',true,'id',new_admin);
 elsif upper(p_action)='UPDATE' then
   if p_admin_id is null or p_role_name is null then raise exception 'INVALID_INPUT'; end if;
   select * into target from public.admins where id=p_admin_id for update;
   if target.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
   if target.user_id=actor.id then raise exception 'SELF_ROLE_CHANGE_FORBIDDEN'; end if;
   select r.priority,r.name into target_priority,old_role from public.roles r where r.id=target.role_id;
   if old_role='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   select * into role_row from public.roles where name=lower(trim(p_role_name)) limit 1;
   if role_row.id is null then raise exception 'ROLE_NOT_FOUND'; end if;
   if role_row.name='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   if actor_role='head_staff' and (role_row.branch<>'moderation' or old_role='head_admin') then raise exception 'STAFF_BRANCH_FORBIDS'; end if;
   if role_row.priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   if target_priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   update public.admins set role_id=role_row.id where id=target.id;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
   values(actor.id,actor.telegram_id,'admin.role_change','admin',target.id,jsonb_build_object('role',old_role),jsonb_build_object('role',role_row.name));
   return json_build_object('success',true,'id',target.id,'role',role_row.name);
 elsif upper(p_action)='DELETE' then
   if p_admin_id is null then raise exception 'INVALID_INPUT'; end if;
   select * into target from public.admins where id=p_admin_id for update;
   if target.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
   if target.user_id=actor.id then raise exception 'SELF_REMOVE_FORBIDDEN'; end if;
   select r.name,r.priority,r.branch into old_role,target_priority,role_row.branch from public.roles r where r.id=target.role_id;
   if old_role='owner' then raise exception 'OWNER_CANNOT_BE_REMOVED'; end if;
   if actor_role='head_staff' and role_row.branch<>'moderation' then raise exception 'STAFF_BRANCH_FORBIDS'; end if;
   if target_priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   delete from public.admins where id=target.id;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data)
   values(actor.id,actor.telegram_id,'admin.remove','admin',target.id,jsonb_build_object('role',old_role,'user_id',target.user_id));
   return json_build_object('success',true,'id',target.id);
 end if;
 raise exception 'UNKNOWN_ACTION';
end; $function$;

revoke execute on function public.staff_manage_admin(text,uuid,bigint,text) from public,anon;
grant execute on function public.staff_manage_admin(text,uuid,bigint,text) to authenticated;

create or replace function public.bot_set_staff_role(p_actor_tg_id bigint,p_target_tg_id bigint,p_role_name text)
returns json language plpgsql security definer set search_path='' as $function$
declare actor_uid uuid; target_uid uuid; actor_priority integer; actor_role text; desired_role public.roles%rowtype; current_priority integer;
begin
 select id into actor_uid from public.users where telegram_id=p_actor_tg_id and deleted_at is null limit 1;
 select id into target_uid from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if actor_uid=target_uid then raise exception 'SELF_STAFF_ASSIGNMENT'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor_uid and p.key='admin.manage') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select r.priority,r.name into actor_priority,actor_role from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
 select * into desired_role from public.roles where name=lower(trim(p_role_name)) and name not in ('content_maker') limit 1;
 if desired_role.id is null then raise exception 'STAFF_ROLE_NOT_FOUND'; end if;
 if desired_role.name='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
 if actor_role='head_staff' and desired_role.branch<>'moderation' then raise exception 'STAFF_BRANCH_FORBIDS'; end if;
 if desired_role.priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 select coalesce(r.priority,0) into current_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target_uid limit 1;
 if current_priority is not null and actor_priority<=current_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 insert into public.admins(user_id,role_id) values(target_uid,desired_role.id)
 on conflict(user_id) do update set role_id=excluded.role_id;
 return json_build_object('success',true,'role',desired_role.name,'rank_label',desired_role.rank_label,'branch',desired_role.branch,'target_id',target_uid);
end; $function$;

revoke execute on function public.bot_set_staff_role(bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_set_staff_role(bigint,bigint,text) to service_role;

create or replace function public.mc_get_staff_identity(p_user_id uuid)
returns json language sql stable security definer set search_path='' as $function$
 select json_build_object(
  'rank',
    case coalesce(r.name,'participant')
      when 'helper' then 1
      when 'moderator' then 2
      when 'senior_moderator' then 3
      when 'admin' then 4
      when 'head_staff' then 5
      when 'head_admin' then 6
      when 'owner' then 7
      else 0
    end,
  'rank_label',coalesce(r.rank_label,case when coalesce(r.name,'participant')='participant' then '0' else null end),
  'role',coalesce(r.name,'participant'),
  'branch',coalesce(r.branch,'community'),
  'priority',coalesce(r.priority,0)
 )
 from (select p_user_id as user_id) input
 left join public.admins a on a.user_id=input.user_id
 left join public.roles r on r.id=a.role_id;
$function$;

revoke execute on function public.mc_get_staff_identity(uuid) from public,anon,authenticated;
grant execute on function public.mc_get_staff_identity(uuid) to service_role;

create or replace function public.participant_get_server_role()
returns json language sql stable security definer set search_path='' as $function$
 select json_build_object(
  'rank',
    case coalesce(r.name,'participant')
      when 'helper' then 1
      when 'moderator' then 2
      when 'senior_moderator' then 3
      when 'admin' then 4
      when 'head_staff' then 5
      when 'head_admin' then 6
      when 'owner' then 7
      else 0
    end,
  'rank_label',coalesce(r.rank_label,case when coalesce(r.name,'participant')='participant' then '0' else null end),
  'role',coalesce(r.name,'participant'),
  'branch',coalesce(r.branch,'community'),
  'priority',coalesce(r.priority,0)
 )
 from public.users u
 left join public.admins a on a.user_id=u.id
 left join public.roles r on r.id=a.role_id
 where u.auth_user_id=auth.uid() and u.deleted_at is null limit 1;
$function$;

revoke execute on function public.participant_get_server_role() from public,anon;
grant execute on function public.participant_get_server_role() to authenticated;