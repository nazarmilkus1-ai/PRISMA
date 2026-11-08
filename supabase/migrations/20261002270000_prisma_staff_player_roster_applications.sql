-- Include a compact application summary in the staff player roster.
-- Full application history and text remain available via staff_get_player_360.

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
          'id',v.id,
          'telegram_id',v.telegram_id,
          'telegram_username',v.telegram_username,
          'first_name',u.first_name,
          'full_name',v.full_name,
          'minecraft_nickname',v.minecraft_nickname,
          'platform',v.platform,
          'status',v.status,
          'is_whitelisted',v.is_whitelisted,
          'is_banned',v.is_banned,
          'is_muted',v.is_muted,
          'muted_until',v.muted_until,
          'rating',v.rating,
          'activity_score',v.activity_score,
          'last_seen_at',v.last_seen_at,
          'clan_id',v.clan_id,
          'created_at',v.created_at,
          'application_count',coalesce(app.application_count,0),
          'latest_application',app.latest_application
        ) as row_data,
        v.minecraft_nickname as nickname_sort
      from public.player_360 v
      join public.users u on u.id=v.id
      left join lateral (
        select
          count(*)::integer as application_count,
          (
            select json_build_object(
              'id',a2.id,
              'application_no',a2.application_no,
              'status',a2.status,
              'full_name',a2.full_name,
              'age',a2.age,
              'nickname',a2.nickname,
              'platform',a2.platform,
              'discovery_source',a2.discovery_source,
              'birth_date',a2.birth_date,
              'goal',a2.goal,
              'about',a2.about,
              'created_at',a2.created_at,
              'updated_at',a2.updated_at,
              'reviewed_at',a2.reviewed_at,
              'reviewed_by_name',a2.reviewed_by_name,
              'rejection_reason',a2.rejection_reason,
              'staff_notes',a2.staff_notes
            )
            from public.applications a2
            where a2.user_id=v.id
            order by a2.created_at desc,a2.id
            limit 1
          ) as latest_application
        from public.applications a
        where a.user_id=v.id
      ) app on true
      where u.deleted_at is null
        and (
          q=''
          or v.minecraft_nickname ilike '%'||q||'%'
          or v.telegram_username ilike '%'||replace(q,'@','')||'%'
          or v.full_name ilike '%'||q||'%'
          or u.first_name ilike '%'||q||'%'
          or v.telegram_id::text=q
          or exists (
            select 1
            from public.applications a_search
            where a_search.user_id=v.id
              and (
                coalesce(a_search.nickname,'') ilike '%'||q||'%'
                or coalesce(a_search.full_name,'') ilike '%'||q||'%'
                or coalesce(a_search.discovery_source,'') ilike '%'||q||'%'
                or coalesce(a_search.goal,'') ilike '%'||q||'%'
                or coalesce(a_search.about,'') ilike '%'||q||'%'
                or a_search.application_no::text=q
              )
          )
        )
      order by v.minecraft_nickname asc nulls last, v.id
      limit lim
    ) rows_data
  ), '[]'::json);
end;
$function$;

revoke all on function public.staff_list_players(text,integer) from public,anon;
grant execute on function public.staff_list_players(text,integer) to authenticated;
