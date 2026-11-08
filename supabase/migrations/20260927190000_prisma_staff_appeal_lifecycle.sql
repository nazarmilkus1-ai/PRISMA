-- PRISMA v2: staff appeal permissions and lifecycle.

insert into public.permissions(key,description)
values
 ('appeal.view','Просмотр апелляций'),
 ('appeal.manage','Рассмотрение и решение апелляций')
on conflict (key) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key in ('appeal.view','appeal.manage')
where r.name in ('owner','head_admin','admin','moderator')
on conflict do nothing;

create or replace function public.staff_list_appeals(
 p_status text default 'OPEN',
 p_limit integer default 200
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 actor_id uuid;
 filter_status text := upper(trim(coalesce(p_status,'OPEN')));
 lim integer := greatest(1,least(coalesce(p_limit,200),500));
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id
 from public.users u
 join public.admins a on a.user_id=u.id
 join public.role_permissions rp on rp.role_id=a.role_id
 join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='appeal.view'
 limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
 if filter_status not in ('ALL','OPEN','IN_REVIEW','APPROVED','REJECTED') then raise exception 'INVALID_STATUS'; end if;

 return coalesce((
  select json_agg(x order by (x->>'created_at')::timestamptz desc)
  from (
   select json_build_object(
    'id',pa.id,'user_id',pa.user_id,'telegram_id',pa.telegram_id,'punishment_id',pa.punishment_id,
    'reason',pa.reason,'status',pa.status,'reviewed_by_tg_id',pa.reviewed_by_tg_id,'review_note',pa.review_note,
    'created_at',pa.created_at,'updated_at',pa.updated_at,
    'user',json_build_object('minecraft_nickname',u.minecraft_nickname,'telegram_username',u.telegram_username,'full_name',u.full_name),
    'punishment',case when m.id is null then null else json_build_object(
      'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
      'expires_at',m.expires_at,'revoked',m.revoked,'created_at',m.created_at
    ) end
   ) x
   from public.punishment_appeals pa
   join public.users u on u.id=pa.user_id
   left join public.moderation_logs m on m.id=pa.punishment_id
   where filter_status='ALL' or pa.status=filter_status
   order by pa.created_at desc
   limit lim
  ) rows_data
 ),'[]'::json);
end;
$function$;

revoke all on function public.staff_list_appeals(text,integer) from public,anon;
grant execute on function public.staff_list_appeals(text,integer) to authenticated;

create or replace function public.staff_get_appeal(p_appeal_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare actor_uid uuid := (select auth.uid()); actor_id uuid; result json;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select u.id into actor_id
 from public.users u join public.admins a on a.user_id=u.id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
 where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='appeal.view' limit 1;
 if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

 select json_build_object(
  'id',pa.id,'user_id',pa.user_id,'telegram_id',pa.telegram_id,'punishment_id',pa.punishment_id,
  'reason',pa.reason,'status',pa.status,'reviewed_by_tg_id',pa.reviewed_by_tg_id,'review_note',pa.review_note,
  'created_at',pa.created_at,'updated_at',pa.updated_at,
  'user',json_build_object('id',u.id,'minecraft_nickname',u.minecraft_nickname,'telegram_username',u.telegram_username,'full_name',u.full_name),
  'punishment',case when m.id is null then null else json_build_object(
    'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
    'expires_at',m.expires_at,'status',m.status,'revoked',m.revoked,'created_at',m.created_at
  ) end
 ) into result
 from public.punishment_appeals pa
 join public.users u on u.id=pa.user_id
 left join public.moderation_logs m on m.id=pa.punishment_id
 where pa.id=p_appeal_id;

 if result is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 return result;
end;
$function$;

revoke all on function public.staff_get_appeal(uuid) from public,anon;
grant execute on function public.staff_get_appeal(uuid) to authenticated;

create or replace function public.staff_manage_appeal(
 p_appeal_id uuid,
 p_action text,
 p_note text default null
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor_uid uuid := (select auth.uid());
 actor public.users%rowtype;
 target public.users%rowtype;
 appeal public.punishment_appeals%rowtype;
 punishment public.moderation_logs%rowtype;
 action text := upper(trim(p_action));
 new_status text;
 revoke_result json;
 accepted boolean := false;
begin
 if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into actor from public.users where auth_user_id=actor_uid and deleted_at is null limit 1;
 if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
 if not exists(
  select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id
  where a.user_id=actor.id and p.key='appeal.manage'
 ) then raise exception 'PERMISSION_DENIED'; end if;

 select * into appeal from public.punishment_appeals where id=p_appeal_id for update;
 if appeal.id is null then raise exception 'APPEAL_NOT_FOUND'; end if;
 if appeal.status not in ('OPEN','IN_REVIEW') then raise exception 'APPEAL_ALREADY_CLOSED'; end if;

 if action='REVIEW' then new_status:='IN_REVIEW';
 elsif action='REJECT' then new_status:='REJECTED';
 elsif action='APPROVE' then new_status:='APPROVED';
 else raise exception 'UNKNOWN_ACTION'; end if;

 if p_note is not null and char_length(trim(p_note))>5000 then raise exception 'INVALID_NOTE'; end if;

 select * into target from public.users where id=appeal.user_id for update;
 if target.id is null then raise exception 'USER_NOT_FOUND'; end if;

 if action='APPROVE' and appeal.punishment_id is not null then
  select * into punishment from public.moderation_logs where id=appeal.punishment_id for update;
  if punishment.id is not null and not punishment.revoked and punishment.type in ('WARN','MUTE','BAN') then
   revoke_result:=public.staff_revoke_moderation(punishment.id);
  elsif punishment.id is not null and not punishment.revoked and punishment.type='KICK' then
   select exists(
    select 1 from public.applications a where a.user_id=target.id and a.status='ACCEPTED' and not a.is_archived
   ) into accepted;
   update public.users
   set is_whitelisted=case when accepted and not is_banned then true else is_whitelisted end,updated_at=now()
   where id=target.id;
   insert into public.sync_outbox(aggregate_type,aggregate_id,event_type,payload)
   values('user',target.id,'user.moderation.updated',jsonb_build_object('type','UNREGISTER_KICK','appeal_id',appeal.id));
  end if;
 end if;

 update public.punishment_appeals
 set status=new_status,reviewed_by_tg_id=actor.telegram_id,
     review_note=case when p_note is null then review_note else trim(p_note) end,updated_at=now()
 where id=appeal.id;

 insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
 values(
  actor.id,actor.telegram_id,'appeal.'||lower(action),'punishment_appeal',appeal.id,
  jsonb_build_object('status',appeal.status),
  jsonb_build_object('status',new_status,'note',p_note,'punishment_id',appeal.punishment_id)
 );

 return json_build_object(
  'success',true,'appeal_id',appeal.id,'user_id',appeal.user_id,'telegram_id',appeal.telegram_id,
  'punishment_id',appeal.punishment_id,'old_status',appeal.status,'status',new_status,'action',action,
  'revoke_result',revoke_result,'reviewed_by_tg_id',actor.telegram_id
 );
end;
$function$;

revoke all on function public.staff_manage_appeal(uuid,text,text) from public,anon;
grant execute on function public.staff_manage_appeal(uuid,text,text) to authenticated;
