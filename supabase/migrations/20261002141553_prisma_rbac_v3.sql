-- PRISMA v2: project RBAC model aligned with the current staff structure.
alter table public.roles
  add column if not exists branch text not null default 'management',
  add column if not exists rank_label text;

update public.roles set branch='management', rank_label='5', description='Власник проекта; полный доступ к инфраструктуре и базе данных', priority=100 where name='owner';
update public.roles set branch='management', rank_label='4', description='Co-Owner / Head Admin; координация руководителей и сложных конфликтов', priority=80 where name='head_admin';
update public.roles set branch='moderation', rank_label='3', description='Administrator; читы, апелляции, сложные случаи и восстановление вещей', priority=60 where name='admin';
update public.roles set branch='moderation', rank_label='2', description='Senior Moderator; старший модератор и сложные конфликты', priority=50 where name='senior_moderator';
update public.roles set branch='moderation', rank_label='1', description='Moderator; основной контроль игрового процесса и репорты', priority=40 where name='moderator';
update public.roles set branch='moderation', rank_label='0.5', description='Helper / Trainee; помощь игрокам и модерация чата без банов', priority=30 where name='helper';
update public.roles set branch='media', rank_label='legacy', description='Legacy Content Maker; оставлен для совместимости старых записей', priority=5 where name='content_maker';

insert into public.roles(name,description,priority,branch,rank_label)
values
  ('head_staff','Head of Staff / Head Mod; руководитель модерации и staff',70,'moderation','3.5'),
  ('developer','Developer / Tech Admin; разработка и техническое обслуживание сервера',20,'development','special'),
  ('builder','Builder / Map Maker; строительство и работа с картами',12,'development','special'),
  ('game_designer','Game Designer / Content Creator; механики, экономика, контент и события',18,'development','special'),
  ('media','Media / Blogger; специальный медиастатус без админских прав',10,'media','special'),
  ('event_manager','Event Manager; организация мероприятий сообщества',15,'events','special')
on conflict(name) do update set
  description=excluded.description,
  priority=excluded.priority,
  branch=excluded.branch,
  rank_label=excluded.rank_label;

insert into public.permissions(key,description,category) values
  ('appeal.view','Просмотр апелляций','moderation'),
  ('appeal.manage','Рассмотрение и решение апелляций','moderation'),
  ('inventory.restore','Восстановление утраченных вещей','moderation'),
  ('staff.view','Просмотр состава персонала','staff'),
  ('server.monitor','Просмотр технического состояния сервера','development'),
  ('server.manage','Управление сервером','development'),
  ('server.config','Изменение технической конфигурации','development'),
  ('plugin.manage','Управление Minecraft-плагинами','development'),
  ('map.manage','Управление картой и техническими слоями','development'),
  ('build.manage','Управление строительными задачами','development'),
  ('content.manage','Управление игровым контентом','development'),
  ('economy.manage','Управление экономическими настройками','development'),
  ('event.manage','Управление мероприятиями','events'),
  ('calendar.manage','Управление календарём','events'),
  ('event.announce','Публикация анонсов мероприятий','events'),
  ('media.manage','Управление медиаматериалами','media'),
  ('news.manage','Управление новостями','media')
on conflict(key) do update set description=excluded.description, category=excluded.category;

delete from public.role_permissions
where role_id in (
  select id from public.roles
  where name in ('head_staff','developer','builder','game_designer','media','event_manager','senior_moderator')
);

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='head_staff'
  and p.key in (
    'player.view','application.view','application.approve','application.reject',
    'punishment.warn','punishment.mute','punishment.ban','punishment.kick',
    'punishment.remove','punishment.view_history',
    'report.view','report.assign','report.resolve','report.reject',
    'appeal.view','appeal.manage','inventory.restore',
    'admin.manage','admin.view_audit','staff.view',
    'dashboard.view','analytics.view'
  )
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='senior_moderator'
  and p.key in (
    'player.view','report.view','report.assign','report.resolve','report.reject',
    'punishment.warn','punishment.mute','punishment.ban','punishment.kick',
    'punishment.remove','punishment.view_history','appeal.view'
  )
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='developer'
  and p.key in ('server.monitor','server.manage','server.config','plugin.manage','map.manage','dashboard.view')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='builder'
  and p.key in ('build.manage','map.manage')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='game_designer'
  and p.key in ('content.manage','economy.manage','event.manage')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='media'
  and p.key in ('media.manage','news.manage')
on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.name='event_manager'
  and p.key in ('event.manage','calendar.manage','event.announce')
on conflict do nothing;

delete from public.role_permissions
where role_id=(select id from public.roles where name='content_maker')
  and permission_id in (
    select id from public.permissions where key not in ('player.view')
  );

create or replace function public.bot_set_staff_rank(
  p_actor_tg_id bigint,
  p_target_tg_id bigint,
  p_rank integer
)
returns json language plpgsql security definer set search_path='' as $
declare
 actor_uid uuid; target_uid uuid; actor_priority integer; desired_role uuid;
 desired_priority integer; current_priority integer; role_name text;
begin
 if p_rank<1 or p_rank>5 then raise exception 'INVALID_STAFF_RANK'; end if;
 if p_actor_tg_id=p_target_tg_id then raise exception 'SELF_STAFF_ASSIGNMENT'; end if;
 select id into actor_uid from public.users where telegram_id=p_actor_tg_id and deleted_at is null limit 1;
 select id into target_uid from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if not exists(
   select 1 from public.admins a
   join public.role_permissions rp on rp.role_id=a.role_id
   join public.permissions p on p.id=rp.permission_id
   where a.user_id=actor_uid and p.key='admin.manage'
 ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select coalesce(r.priority,0) into actor_priority
 from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
 if actor_priority is null then raise exception 'ADMIN_NOT_FOUND'; end if;

 desired_role:=case p_rank
  when 1 then (select id from public.roles where name='moderator' limit 1)
  when 2 then (select id from public.roles where name='senior_moderator' limit 1)
  when 3 then (select id from public.roles where name='admin' limit 1)
  when 4 then (select id from public.roles where name='head_admin' limit 1)
  when 5 then (select id from public.roles where name='owner' limit 1)
 end;

 select priority,name into desired_priority,role_name from public.roles where id=desired_role;
 if desired_role is null then raise exception 'STAFF_ROLE_NOT_FOUND'; end if;
 if actor_priority<=desired_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;
 select coalesce(r.priority,0) into current_priority
 from public.admins a join public.roles r on r.id=a.role_id where a.user_id=target_uid limit 1;
 if current_priority is not null and actor_priority<=current_priority then raise exception 'STAFF_HIERARCHY_FORBIDS'; end if;

 insert into public.admins(user_id,role_id) values(target_uid,desired_role)
 on conflict(user_id) do update set role_id=excluded.role_id;

 return json_build_object('success',true,'rank',p_rank,'role',role_name,'target_id',target_uid);
end $;

revoke execute on function public.bot_set_staff_rank(bigint,bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_set_staff_rank(bigint,bigint,integer) to service_role;

create or replace function public.bot_set_staff_role(
  p_actor_tg_id bigint,
  p_target_tg_id bigint,
  p_role_name text
)
returns json language plpgsql security definer set search_path='' as $
declare actor_uid uuid; target_uid uuid; actor_priority integer; actor_role text; desired_role public.roles%rowtype; current_priority integer;
begin
 select id into actor_uid from public.users where telegram_id=p_actor_tg_id and deleted_at is null limit 1;
 select id into target_uid from public.users where telegram_id=p_target_tg_id and deleted_at is null limit 1;
 if actor_uid is null or target_uid is null then raise exception 'USER_NOT_FOUND'; end if;
 if actor_uid=target_uid then raise exception 'SELF_STAFF_ASSIGNMENT'; end if;
 if not exists(
   select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
   where a.user_id=actor_uid and p.key='admin.manage'
 ) then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select coalesce(r.priority,0),r.name into actor_priority,actor_role
 from public.admins a join public.roles r on r.id=a.role_id where a.user_id=actor_uid limit 1;
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
end $$;

revoke execute on function public.bot_set_staff_role(bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.bot_set_staff_role(bigint,bigint,text) to service_role;