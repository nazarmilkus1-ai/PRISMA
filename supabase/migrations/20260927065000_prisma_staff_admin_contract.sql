create or replace function public.staff_manage_admin(p_action text,p_admin_id uuid default null,p_telegram_id bigint default null,p_role_name text default null)
returns json language plpgsql security definer set search_path='' as $$
declare actor_uid uuid:=auth.uid(); actor public.users%rowtype; target public.admins%rowtype; target_user public.users%rowtype; role_row public.roles%rowtype; old_role text; target_priority int; actor_priority int; new_admin uuid;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=actor.id and p.key='admin.manage') then raise exception 'PERMISSION_DENIED'; end if;
 select coalesce(r.priority,0) into actor_priority from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor.id limit 1;
 if upper(p_action)='CREATE' then
   if p_telegram_id is null or p_role_name is null then raise exception 'INVALID_INPUT'; end if;
   select * into role_row from public.roles where name=lower(trim(p_role_name)) limit 1;
   if role_row.id is null then raise exception 'ROLE_NOT_FOUND'; end if;
   if role_row.name='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   if role_row.priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   select * into target_user from public.users where telegram_id=p_telegram_id and deleted_at is null limit 1;
   if target_user.id is null then insert into public.users(telegram_id) values(p_telegram_id) returning * into target_user; end if;
   if exists(select 1 from public.admins where user_id=target_user.id) then raise exception 'ALREADY_ADMIN'; end if;
   insert into public.admins(user_id,role_id) values(target_user.id,role_row.id) returning id into new_admin;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data) values(actor.id,actor.telegram_id,'admin.create','admin',new_admin,jsonb_build_object('telegram_id',p_telegram_id,'role',role_row.name));
   return json_build_object('success',true,'id',new_admin);
 elsif upper(p_action)='UPDATE' then
   if p_admin_id is null or p_role_name is null then raise exception 'INVALID_INPUT'; end if;
   select * into target from public.admins where id=p_admin_id for update;
   if target.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
   select r.priority,r.name into target_priority,old_role from public.roles r where r.id=target.role_id;
   if old_role='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   select * into role_row from public.roles where name=lower(trim(p_role_name)) limit 1;
   if role_row.id is null then raise exception 'ROLE_NOT_FOUND'; end if;
   if role_row.name='owner' and actor_priority<100 then raise exception 'OWNER_ONLY'; end if;
   if role_row.priority>=actor_priority and target.user_id<>actor.id then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   update public.admins set role_id=role_row.id where id=target.id;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data) values(actor.id,actor.telegram_id,'admin.role_change','admin',target.id,jsonb_build_object('role',old_role),jsonb_build_object('role',role_row.name));
   return json_build_object('success',true,'id',target.id,'role',role_row.name);
 elsif upper(p_action)='DELETE' then
   if p_admin_id is null then raise exception 'INVALID_INPUT'; end if;
   select * into target from public.admins where id=p_admin_id for update;
   if target.id is null then raise exception 'ADMIN_NOT_FOUND'; end if;
   select r.name,r.priority into old_role,target_priority from public.roles r where r.id=target.role_id;
   if old_role='owner' then raise exception 'OWNER_CANNOT_BE_REMOVED'; end if;
   if target.user_id=actor.id then raise exception 'SELF_REMOVE_FORBIDDEN'; end if;
   if target_priority>=actor_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
   delete from public.admins where id=target.id;
   insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data) values(actor.id,actor.telegram_id,'admin.remove','admin',target.id,jsonb_build_object('role',old_role,'user_id',target.user_id));
   return json_build_object('success',true,'id',target.id);
 end if;
 raise exception 'UNKNOWN_ACTION';
end; $$;
revoke execute on function public.staff_manage_admin(text,uuid,bigint,text) from public,anon;
grant execute on function public.staff_manage_admin(text,uuid,bigint,text) to authenticated;