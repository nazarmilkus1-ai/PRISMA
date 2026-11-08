-- PRISMA moderation action and Minecraft lookup consistency fixes.
CREATE OR REPLACE FUNCTION public.get_minecraft_user(p_nickname text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare result_row public.users%rowtype;
begin
  select * into result_row
  from public.users
  where deleted_at is null
    and lower(trim(minecraft_nickname))=lower(trim(p_nickname))
  limit 1;

  if not found then
    return json_build_object('error','USER_NOT_FOUND');
  end if;

  return json_build_object(
    'id',result_row.id,
    'telegram_id',result_row.telegram_id,
    'minecraft_nickname',result_row.minecraft_nickname,
    'clan_id',result_row.clan_id,
    'is_muted',result_row.is_muted,
    'muted_until',result_row.muted_until,
    'status',result_row.status,
    'is_whitelisted',result_row.is_whitelisted,
    'is_banned',result_row.is_banned,
    'ban_reason',result_row.ban_reason
  );
end;
$function$;

-- SYSTEM_ACTION rows are history markers, not active punishments.
-- Keep them in a valid moderation status so they remain queryable without
-- ever becoming active enforcement records.
CREATE OR REPLACE FUNCTION public.bot_lift_punishment(
  p_user_tg_id bigint,
  p_type text,
  p_admin_tg_id bigint
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  uid uuid;
  admin_uid uuid;
  pid uuid;
  new_id uuid;
  typ text:=upper(trim(p_type));
begin
  select id into uid from public.users where telegram_id=p_user_tg_id for update;
  select a.user_id into admin_uid
  from public.admins a
  join public.users u on u.id=a.user_id
  where u.telegram_id=p_admin_tg_id
  limit 1;

  if uid is null or admin_uid is null then raise exception 'USER_OR_ADMIN_NOT_FOUND'; end if;
  if typ not in ('WARN','MUTE') then raise exception 'UNSUPPORTED_LIFT_TYPE'; end if;

  select m.id into pid
  from public.moderation_logs m
  where m.target_id=uid
    and m.type=typ
    and m.status='ACTIVE'
    and m.revoked=false
    and (m.expires_at is null or m.expires_at>now())
  order by m.created_at desc
  limit 1;

  if pid is null then raise exception 'NO_ACTIVE_PUNISHMENT'; end if;

  update public.moderation_logs
     set revoked=true,
         revoked_at=now(),
         revoked_by_tg_id=p_admin_tg_id,
         status='REVOKED',
         applied_at=coalesce(applied_at,now())
   where id=pid;

  if typ='MUTE' then
    update public.users
       set is_muted=false,muted_until=null,updated_at=now()
     where id=uid;
  else
    update public.users
       set warning_count=greatest(0,warning_count-1),updated_at=now()
     where id=uid;
  end if;

  insert into public.moderation_logs(
    target_id,issued_by_tg_id,issued_by_name,type,reason,source,status,applied_at,revoked
  )
  values(
    uid,p_admin_tg_id,null,
    case when typ='MUTE' then 'UNMUTE' else 'UNWARN' end,
    'Покарання знято','BOT','REVOKED',null,true
  )
  returning id into new_id;

  return json_build_object(
    'success',true,
    'punishment_id',pid,
    'action_id',new_id,
    'type',typ
  );
end;
$function$;
