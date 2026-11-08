-- PRISMA v2: authenticated staff player roster and 360-degree read contracts.

create or replace function public.staff_list_players(
  p_search text default '',
  p_limit integer default 500
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  q text := btrim(coalesce(p_search,''));
  lim integer := greatest(1, least(coalesce(p_limit,500),500));
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

  return coalesce((
    select json_agg(row_data order by nickname_sort nulls last, row_data->>'id')
    from (
      select
        json_build_object(
          'id',v.id,'telegram_id',v.telegram_id,'telegram_username',v.telegram_username,
          'first_name',u.first_name,'full_name',v.full_name,
          'minecraft_nickname',v.minecraft_nickname,'platform',v.platform,'status',v.status,
          'is_whitelisted',v.is_whitelisted,'is_banned',v.is_banned,'is_muted',v.is_muted,
          'muted_until',v.muted_until,'rating',v.rating,'activity_score',v.activity_score,
          'last_seen_at',v.last_seen_at,'clan_id',v.clan_id,'created_at',v.created_at
        ) as row_data,
        v.minecraft_nickname as nickname_sort
      from public.player_360 v
      join public.users u on u.id=v.id
      where u.deleted_at is null
        and (
          q=''
          or v.minecraft_nickname ilike '%'||q||'%'
          or v.telegram_username ilike '%'||q||'%'
          or v.full_name ilike '%'||q||'%'
          or u.first_name ilike '%'||q||'%'
          or v.telegram_id::text=q
        )
      order by v.minecraft_nickname asc nulls last, v.id
      limit lim
    ) rows_data
  ), '[]'::json);
end;
$function$;

revoke all on function public.staff_list_players(text,integer) from public,anon;
grant execute on function public.staff_list_players(text,integer) to authenticated;

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
    'first_name',u.first_name,'last_name',u.last_name,'age',u.age,'birth_date',u.birth_date
  )
  into base_player
  from public.player_360 v
  join public.users u on u.id=v.id
  where v.id=p_user_id and u.deleted_at is null;

  if base_player is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select coalesce(json_agg(x order by x->>'created_at' desc),'[]'::json)
  into applications_data
  from (
    select json_build_object(
      'id',a.id,'status',a.status,'nickname',a.nickname,'platform',a.platform,
      'discovery_source',a.discovery_source,'created_at',a.created_at,
      'reviewed_at',a.reviewed_at,'reviewed_by_name',a.reviewed_by_name,
      'rejection_reason',a.rejection_reason,'birth_date',a.birth_date,
      'goal',a.goal,'about',a.about
    ) as x
    from public.applications a
    where a.user_id=p_user_id
    order by a.created_at desc
    limit 30
  ) rows_data;

  select coalesce(json_agg(x order by x->>'created_at' desc),'[]'::json)
  into moderation_data
  from (
    select json_build_object(
      'id',m.id,'type',m.type,'reason',m.reason,'duration_minutes',m.duration_minutes,
      'expires_at',m.expires_at,'source',m.source,'issued_by_name',m.issued_by_name,
      'created_at',m.created_at,'revoked',m.revoked,'revoked_at',m.revoked_at,
      'revoked_by_name',m.revoked_by_name
    ) as x
    from public.moderation_logs m
    where m.target_id=p_user_id
    order by m.created_at desc
    limit 100
  ) rows_data;

  select coalesce(json_agg(x order by x->>'created_at' desc),'[]'::json)
  into reports_data
  from (
    select json_build_object(
      'id',r.id,'ticket_no',r.ticket_no,'type',r.type,'target_nickname',r.target_nickname,
      'description',r.description,'status',r.status,'priority',r.priority,'category',r.category,
      'created_at',r.created_at,'resolved_at',r.resolved_at
    ) as x
    from public.reports r
    where r.user_id=p_user_id
    order by r.created_at desc
    limit 50
  ) rows_data;

  select coalesce(json_agg(x order by x->>'created_at' desc),'[]'::json)
  into votes_data
  from (
    select json_build_object(
      'id',pv.id,'poll_id',pv.poll_id,'option_id',pv.option_id,'created_at',pv.created_at
    ) as x
    from public.poll_votes pv
    where pv.user_id=p_user_id
    order by pv.created_at desc
    limit 100
  ) rows_data;

  select case when cm.user_id is null then null else json_build_object(
    'clan_id',cm.clan_id,'role',cm.role,'joined_at',cm.joined_at,'status',cm.status,
    'clans',case when c.id is null then null else json_build_object(
      'id',c.id,'name',c.name,'tag',c.tag,'rating',c.rating,'status',c.status
    ) end
  ) end
  into clan_data
  from public.clan_members cm
  left join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id
  limit 1;

  select coalesce(json_agg(x),'[]'::json)
  into achievements_data
  from (
    select to_jsonb(ua) as x
    from public.user_achievements ua
    where ua.user_id=p_user_id
    limit 50
  ) rows_data;

  select coalesce(json_agg(x),'[]'::json)
  into quests_data
  from (
    select to_jsonb(uq) as x
    from public.user_quests uq
    where uq.user_id=p_user_id
    limit 50
  ) rows_data;

  return json_build_object(
    'player',base_player,'applications',applications_data,'moderation',moderation_data,
    'reports',reports_data,'votes',votes_data,'clan',clan_data,
    'achievements',achievements_data,'quests',quests_data
  );
end;
$function$;

revoke all on function public.staff_get_player_360(uuid) from public,anon;
grant execute on function public.staff_get_player_360(uuid) to authenticated;
