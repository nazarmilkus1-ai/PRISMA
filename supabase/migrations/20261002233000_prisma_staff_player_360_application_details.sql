-- Expand the staff player 360 payload so the panel can render the complete application.

create or replace function public.staff_get_player_360(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  base_player json;
  applications_data json;
  moderation_data json;
  reports_data json;
  votes_data json;
  clan_data json;
  achievements_data json;
  quests_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and p.key='player.view'
  limit 1;

  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select to_jsonb(v) || jsonb_build_object(
    'first_name',u.first_name,
    'last_name',u.last_name,
    'age',u.age,
    'birth_date',u.birth_date,
    'telegram_username',u.telegram_username,
    'telegram_id',u.telegram_id
  )
  into base_player
  from public.player_360 v
  join public.users u on u.id=v.id
  where v.id=p_user_id and u.deleted_at is null;

  if base_player is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(json_agg(json_build_object(
    'id',a.id,
    'application_no',a.application_no,
    'status',a.status,
    'full_name',a.full_name,
    'age',a.age,
    'nickname',a.nickname,
    'platform',a.platform,
    'discovery_source',a.discovery_source,
    'created_at',a.created_at,
    'updated_at',a.updated_at,
    'reviewed_at',a.reviewed_at,
    'reviewed_by_tg_id',a.reviewed_by_tg_id,
    'reviewed_by_name',a.reviewed_by_name,
    'rejection_reason',a.rejection_reason,
    'birth_date',a.birth_date,
    'goal',a.goal,
    'about',a.about,
    'staff_notes',a.staff_notes,
    'cooldown_until',a.cooldown_until,
    'is_archived',a.is_archived
  ) order by a.created_at desc),'[]'::json)
  into applications_data
  from public.applications a
  where a.user_id=p_user_id
  limit 30;

  select coalesce(json_agg(json_build_object(
    'id',m.id,
    'type',m.type,
    'reason',m.reason,
    'duration_minutes',m.duration_minutes,
    'expires_at',m.expires_at,
    'source',m.source,
    'issued_by_name',m.issued_by_name,
    'created_at',m.created_at,
    'revoked',m.revoked,
    'revoked_at',m.revoked_at,
    'revoked_by_name',m.revoked_by_name
  ) order by m.created_at desc),'[]'::json)
  into moderation_data
  from public.moderation_logs m
  where m.target_id=p_user_id
  limit 100;

  select coalesce(json_agg(json_build_object(
    'id',r.id,
    'ticket_no',r.ticket_no,
    'type',r.type,
    'target_nickname',r.target_nickname,
    'description',r.description,
    'status',r.status,
    'priority',r.priority,
    'category',r.category,
    'created_at',r.created_at,
    'resolved_at',r.resolved_at
  ) order by r.created_at desc),'[]'::json)
  into reports_data
  from public.reports r
  where r.user_id=p_user_id
  limit 50;

  select coalesce(json_agg(json_build_object(
    'id',pv.id,
    'poll_id',pv.poll_id,
    'option_id',pv.option_id,
    'created_at',pv.created_at
  ) order by pv.created_at desc),'[]'::json)
  into votes_data
  from public.poll_votes pv
  where pv.user_id=p_user_id
  limit 100;

  select case when cm.user_id is null then null else json_build_object(
    'clan_id',cm.clan_id,
    'role',cm.role,
    'joined_at',cm.joined_at,
    'status',cm.status,
    'clans',case when c.id is null then null else json_build_object(
      'id',c.id,
      'name',c.name,
      'tag',c.tag,
      'rating',c.rating,
      'status',c.status
    ) end
  ) end
  into clan_data
  from public.clan_members cm
  left join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id
  limit 1;

  select coalesce(json_agg(to_jsonb(ua)),'[]'::json)
  into achievements_data
  from public.user_achievements ua
  where ua.user_id=p_user_id
  limit 50;

  select coalesce(json_agg(to_jsonb(uq)),'[]'::json)
  into quests_data
  from public.user_quests uq
  where uq.user_id=p_user_id
  limit 50;

  return json_build_object(
    'player',base_player,
    'applications',applications_data,
    'moderation',moderation_data,
    'reports',reports_data,
    'votes',votes_data,
    'clan',clan_data,
    'achievements',achievements_data,
    'quests',quests_data
  );
end;
$function$;

revoke all on function public.staff_get_player_360(uuid) from public,anon;
grant execute on function public.staff_get_player_360(uuid) to authenticated;
