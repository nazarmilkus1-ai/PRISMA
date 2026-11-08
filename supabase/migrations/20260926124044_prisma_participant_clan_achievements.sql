CREATE OR REPLACE FUNCTION private.prisma_participant_get_clan(p_user_id uuid, p_clan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  result jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select jsonb_build_object(
    'clan', jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'tag', c.tag,
      'type', c.type,
      'description', c.description,
      'rating', c.rating,
      'points', c.points,
      'level', c.level,
      'xp', c.xp,
      'wins', c.wins,
      'losses', c.losses,
      'color', c.color,
      'avatar_url', c.avatar_url,
      'created_at', c.created_at
    ),
    'members', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'nickname', u.minecraft_nickname,
          'full_name', null,
          'platform', u.platform,
          'level', u.level,
          'rating', u.rating,
          'role', cm.role,
          'joined_at', cm.joined_at,
          'last_seen_at', u.last_seen_at
        )
        order by
          case cm.role
            when 'owner' then 0
            when 'co_owner' then 1
            when 'officer' then 2
            when 'recruit' then 4
            else 3
          end,
          cm.joined_at asc
      )
      from public.clan_members cm
      join public.users u on u.id=cm.user_id
      where cm.clan_id=c.id
        and cm.status='active'
        and u.deleted_at is null
        and u.status='ACCEPTED'::public.application_status
        and not u.is_banned
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ca.id,
          'kind', ca.kind,
          'xp', ca.xp,
          'created_at', ca.created_at,
          'nickname', u.minecraft_nickname
        )
        order by ca.created_at desc
      )
      from public.clan_activity ca
      left join public.users u on u.id=ca.user_id
      where ca.clan_id=c.id
      limit 50
    ), '[]'::jsonb),
    'villages', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', v.id,
          'name', v.name,
          'world', v.world,
          'center_x', v.center_x,
          'center_y', v.center_y,
          'center_z', v.center_z,
          'radius', v.radius,
          'status', v.status,
          'created_at', v.created_at
        )
        order by v.created_at asc
      )
      from public.clan_villages v
      where v.clan_id=c.id and v.status='active'
    ), '[]'::jsonb),
    'wars', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', w.id,
          'opponent', case when w.clan_a=c.id then ca.name else cb.name end,
          'opponent_tag', case when w.clan_a=c.id then ca.tag else cb.tag end,
          'status', w.status,
          'scheduled_at', w.scheduled_at,
          'score_for', case when w.clan_a=c.id then w.score_a else w.score_b end,
          'score_against', case when w.clan_a=c.id then w.score_b else w.score_a end,
          'winner', case
            when w.winner_clan_id=c.id then true
            when w.winner_clan_id is null then null
            else false
          end,
          'created_at', w.created_at
        )
        order by w.created_at desc
      )
      from public.clan_wars w
      join public.clans ca on ca.id=w.clan_a
      join public.clans cb on cb.id=w.clan_b
      where (w.clan_a=c.id or w.clan_b=c.id)
      limit 50
    ), '[]'::jsonb),
    'achievements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'achievement_id', ca.achievement_id,
          'unlocked_at', ca.unlocked_at,
          'achievements', jsonb_build_object(
            'id', a.id,
            'code', a.code,
            'title', a.title,
            'description', a.description,
            'icon', a.icon,
            'xp_reward', a.xp_reward
          )
        )
        order by ca.unlocked_at desc
      )
      from (
        select clan_id,achievement_id,unlocked_at
        from public.clan_achievements
        where clan_id=c.id
        order by unlocked_at desc
        limit 100
      ) ca
      join public.achievements a on a.id=ca.achievement_id
    ), '[]'::jsonb),
    'announcements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'title', a.title,
          'body', a.body,
          'created_at', a.created_at,
          'nickname', u.minecraft_nickname
        )
        order by a.created_at desc
      )
      from public.clan_announcements a
      left join public.users u on u.id=a.author_id
      where a.clan_id=c.id
      limit 20
    ), '[]'::jsonb)
  )
  into result
  from public.clans c
  where c.id=p_clan_id
    and c.deleted_at is null
    and c.status='active';

  if result is null then raise exception 'CLAN_NOT_FOUND'; end if;
  return result;
end;
$function$;