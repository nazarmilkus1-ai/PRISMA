-- The canonical Minecraft identity is the approved nickname.
CREATE OR REPLACE FUNCTION public.get_user_profile(p_tg_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare profile record; warns integer;
begin
  select usr.*,app.status as application_status
    into profile
  from public.users usr
  left join lateral(
    select applications.status
    from public.applications
    where applications.user_id=usr.id
    order by applications.created_at desc,applications.id desc
    limit 1
  ) app on true
  where usr.telegram_id=p_tg_id;

  if not found then return json_build_object('error','USER_NOT_FOUND'); end if;

  select count(*) into warns
  from public.moderation_logs
  where target_id=profile.id and type='WARN' and revoked=false;

  return json_build_object(
    'id',profile.id,
    'tg_id',profile.telegram_id,
    'username',profile.telegram_username,
    'full_name',profile.full_name,
    'status',profile.status,
    'birth_date',profile.birth_date,
    'minecraft_nick',profile.minecraft_nickname,
    'platform',profile.platform,
    'is_whitelisted',profile.is_whitelisted,
    'application_status',profile.application_status,
    'rating',profile.rating,
    'activity_score',profile.activity_score,
    'level',profile.level,
    'xp',profile.xp,
    'last_seen_at',profile.last_seen_at,
    'active_warns',warns,
    'is_banned',profile.is_banned,
    'banned_until',profile.banned_until,
    'is_muted',profile.is_muted,
    'muted_until',profile.muted_until,
    'clan_id',profile.clan_id
  );
end;
$function$;
