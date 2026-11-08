-- Keep the participant player profile payload minimal: only fields used by the
-- community-facing profile are returned. Private/user-sensitive identity fields
-- remain inside public.users and are not exposed by this participant gateway.

CREATE OR REPLACE FUNCTION private.prisma_participant_get_player_profile(p_user_id uuid, p_nickname text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  target public.users%rowtype;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select u.* into target
  from public.users u
  where u.deleted_at is null
    and u.status='ACCEPTED'
    and not u.is_banned
    and u.minecraft_nickname is not null
    and lower(u.minecraft_nickname)=lower(trim(p_nickname))
  limit 1;

  if target.id is null then return null; end if;

  return jsonb_build_object(
    'user', jsonb_build_object(
      'id',target.id,
      'minecraft_nickname',target.minecraft_nickname,
      'platform',target.platform,
      'rating',target.rating,
      'activity_score',target.activity_score,
      'level',target.level,
      'xp',target.xp,
      'last_seen_at',target.last_seen_at,
      'created_at',target.created_at,
      'clan_id',target.clan_id
    ),
    'stats', coalesce((
      select to_jsonb(s) from (
        select ps.kills,ps.deaths,ps.playtime_minutes,ps.blocks_placed,ps.blocks_broken,
               ps.mobs_killed,ps.distance_walked,ps.damage_dealt,ps.damage_taken,ps.updated_at
        from public.player_stats ps where ps.user_id=target.id
      ) s
    ), '{}'::jsonb),
    'achievements', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.unlocked_at desc)
      from (
        select ua.achievement_id,ua.unlocked_at,
               jsonb_build_object(
                 'id',ac.id,'code',ac.code,'title',ac.title,'description',ac.description,
                 'icon',ac.icon,'xp_reward',ac.xp_reward
               ) as achievements
        from public.user_achievements ua
        join public.achievements ac on ac.id=ua.achievement_id
        where ua.user_id=target.id
        order by ua.unlocked_at desc
        limit 100
      ) a
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.created_at desc)
      from (
        select ae.id,ae.source,ae.points,ae.created_at
        from public.activity_events ae where ae.user_id=target.id
        order by ae.created_at desc limit 20
      ) e
    ), '[]'::jsonb),
    'clan', case when target.clan_id is null then null else (
      select jsonb_build_object('id',c.id,'name',c.name,'tag',c.tag,'rating',c.rating,'level',c.level,'color',c.color,'avatar_url',c.avatar_url)
      from public.clans c where c.id=target.clan_id and c.deleted_at is null and c.status='active'
    ) end,
    'membership', case when target.clan_id is null then null else (
      select jsonb_build_object('role',cm.role,'joined_at',cm.joined_at,'status',cm.status)
      from public.clan_members cm where cm.user_id=target.id and cm.clan_id=target.clan_id and cm.status='active' limit 1
    ) end,
    'rating_history', coalesce((
      select jsonb_agg(to_jsonb(h) order by h.created_at desc)
      from (
        select rh.rating,rh.delta,rh.reason,rh.created_at
        from public.rating_history rh where rh.user_id=target.id
        order by rh.created_at desc limit 12
      ) h
    ), '[]'::jsonb),
    'server_role', coalesce((
      select r.name
      from public.admins ad join public.roles r on r.id=ad.role_id
      where ad.user_id=target.auth_user_id
      order by r.priority desc limit 1
    ), 'Участник')
  );
end;
$function$;