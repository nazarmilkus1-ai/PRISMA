create or replace function public.bot_lift_chat_punishment(p_chat_id bigint,p_user_tg_id bigint,p_type text,p_admin_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare uid uuid; admin_uid uuid; pid uuid; typ text:=upper(trim(p_type));
begin
 select id into uid from public.users where telegram_id=p_user_tg_id and deleted_at is null limit 1;
 select id into admin_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
 if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
 if typ not in ('WARN','MUTE','BAN') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;
 if not exists(select 1 from public.admins a join public.users u on u.id=a.user_id join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where u.telegram_id=p_admin_tg_id and p.key='punishment.remove') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 select m.id into pid from public.moderation_logs m where m.chat_id=p_chat_id and m.target_id=uid and m.type=typ and m.status='ACTIVE' and m.revoked=false and (m.expires_at is null or m.expires_at>now()) order by m.created_at desc limit 1;
 if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;
 update public.moderation_logs set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED' where id=pid;
 return json_build_object('success',true,'punishment_id',pid,'type',typ);
end $$;

create or replace function public.bot_revoke_chat_punishment(p_punishment_id uuid,p_admin_tg_id bigint)
returns json language plpgsql security definer set search_path=public as $$
declare admin_uid uuid;
begin
 select id into admin_uid from public.users where telegram_id=p_admin_tg_id and deleted_at is null limit 1;
 if admin_uid is null then raise exception 'ADMIN_NOT_FOUND'; end if;
 if not exists(select 1 from public.admins a join public.role_permissions rp on rp.role_id=a.role_id join public.permissions p on p.id=rp.permission_id where a.user_id=admin_uid and p.key='punishment.remove') then raise exception 'ADMIN_LACKS_PERMISSION'; end if;
 if not exists(select 1 from public.moderation_logs where id=p_punishment_id and chat_id is not null and status='ACTIVE' and revoked=false) then raise exception 'PUNISHMENT_NOT_FOUND'; end if;
 update public.moderation_logs set revoked=true,revoked_at=now(),revoked_by_tg_id=p_admin_tg_id,status='REVOKED' where id=p_punishment_id;
 return json_build_object('success',true,'punishment_id',p_punishment_id);
end $$;

create or replace function public.bot_get_chat_mutes(p_chat_id bigint)
returns json language sql security definer set search_path=public as $$
 select coalesce(json_agg(x order by x.expires_at asc nulls last,x.created_at desc),'[]'::json)
 from (
  select m.id,u.telegram_id as tg_id,u.full_name,u.telegram_username,m.reason,m.expires_at,m.created_at
  from public.moderation_logs m join public.users u on u.id=m.target_id
  where m.chat_id=p_chat_id and m.type='MUTE' and m.status='ACTIVE' and m.revoked=false
    and (m.expires_at is null or m.expires_at>now()) and u.deleted_at is null
  order by m.expires_at asc nulls last,m.created_at desc limit 100
 ) x $$;