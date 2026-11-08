-- PRISMA v2: canonical authenticated dashboard read gateway.
-- The caller is always resolved from auth.uid(); a client cannot choose another user_id.
create or replace function public.participant_get_dashboard()
returns jsonb
language sql
security definer
set search_path to ''
as $function$
with me as (
  select
    u.id,
    u.telegram_username,
    u.first_name,
    u.last_name,
    u.full_name,
    u.age,
    u.minecraft_nickname,
    u.platform,
    u.status,
    u.is_whitelisted,
    u.is_banned,
    u.ban_reason,
    u.is_muted,
    u.muted_until,
    u.rating,
    u.activity_score,
    u.level,
    u.xp,
    u.last_seen_at,
    u.last_login_at,
    u.created_at,
    u.clan_id,
    u.locale,
    u.profile_links,
    u.social_visibility
  from public.users u
  where u.auth_user_id = (select auth.uid())
    and u.deleted_at is null
  limit 1
),
dashboard_user as (
  select *
  from me
  limit 1
),
dashboard_application as (
  select
    a.id,
    a.application_no,
    a.full_name,
    a.age,
    a.nickname,
    a.platform,
    a.status,
    a.rejection_reason,
    a.goal,
    a.about,
    a.discovery_source,
    a.created_at,
    a.updated_at,
    a.reviewed_at
  from public.applications a
  where a.user_id = (select id from dashboard_user)
  order by a.created_at desc
  limit 1
),
dashboard_clan as (
  select
    c.id,
    c.name,
    c.tag,
    c.description,
    c.rating,
    c.points,
    c.level,
    c.xp,
    c.wins,
    c.losses,
    c.color,
    c.avatar_url,
    c.created_at
  from public.clans c
  where c.id = (select clan_id from dashboard_user)
    and c.deleted_at is null
  limit 1
),
dashboard_membership as (
  select
    cm.clan_id,
    cm.user_id,
    cm.role,
    cm.status,
    cm.joined_at
  from public.clan_members cm
  where cm.user_id = (select id from dashboard_user)
    and cm.status = 'active'
  limit 1
),
dashboard_invitations as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ci.id,
      'clan_id', ci.clan_id,
      'status', ci.status,
      'expires_at', ci.expires_at,
      'created_at', ci.created_at,
      'clans', case
        when c.id is null then null
        else jsonb_build_object('name', c.name, 'tag', c.tag)
      end
    )
    order by ci.created_at desc
  ), '[]'::jsonb) as value
  from public.clan_invitations ci
  left join public.clans c on c.id = ci.clan_id
  where ci.invitee_id = (select id from dashboard_user)
    and ci.status = 'pending'
    and ci.expires_at > now()
),
dashboard_reports as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'ticket_no', r.ticket_no,
      'type', r.type,
      'target_nickname', r.target_nickname,
      'description', r.description,
      'status', r.status,
      'priority', r.priority,
      'category', r.category,
      'created_at', r.created_at,
      'updated_at', r.updated_at,
      'resolved_at', r.resolved_at
    )
    order by r.created_at desc
  ), '[]'::jsonb) as value
  from (
    select *
    from public.reports
    where user_id = (select id from dashboard_user)
    order by created_at desc
    limit 10
  ) r
),
dashboard_notifications as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', n.id,
      'kind', n.kind,
      'title', n.title,
      'body', n.body,
      'data', n.data,
      'status', n.status,
      'created_at', n.created_at
    )
    order by n.created_at desc
  ), '[]'::jsonb) as value
  from (
    select *
    from public.notifications
    where user_id = (select id from dashboard_user)
    order by created_at desc
    limit 12
  ) n
),
dashboard_preferences as (
  select jsonb_build_object(
    'news', p.news,
    'events', p.events,
    'server_status', p.server_status,
    'clan_news', p.clan_news,
    'social', p.social,
    'battles', p.battles,
    'market', p.market,
    'moderation', p.moderation,
    'polls', p.polls
  ) as value
  from public.notification_preferences p
  where p.user_id = (select id from dashboard_user)
  limit 1
),
dashboard_stats as (
  select jsonb_build_object(
    'user_id', s.user_id,
    'kills', s.kills,
    'deaths', s.deaths,
    'playtime_minutes', s.playtime_minutes,
    'blocks_placed', s.blocks_placed,
    'blocks_broken', s.blocks_broken,
    'mobs_killed', s.mobs_killed,
    'distance_walked', s.distance_walked,
    'damage_dealt', s.damage_dealt,
    'damage_taken', s.damage_taken,
    'updated_at', s.updated_at
  ) as value
  from public.player_stats s
  where s.user_id = (select id from dashboard_user)
  limit 1
),
dashboard_achievements as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'achievement_id', ua.achievement_id,
      'unlocked_at', ua.unlocked_at,
      'achievements', case
        when a.id is null then null
        else jsonb_build_object(
          'id', a.id,
          'code', a.code,
          'title', a.title,
          'description', a.description,
          'icon', a.icon,
          'xp_reward', a.xp_reward
        )
      end
    )
    order by ua.unlocked_at desc
  ), '[]'::jsonb) as value
  from (
    select *
    from public.user_achievements
    where user_id = (select id from dashboard_user)
    order by unlocked_at desc
    limit 30
  ) ua
  left join public.achievements a on a.id = ua.achievement_id
),
dashboard_polls as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'question', p.question,
      'description', p.description,
      'kind', p.kind,
      'kind_text', p.kind_text,
      'expires_at', p.expires_at,
      'status', p.status,
      'visibility', p.visibility,
      'allow_multiple', p.allow_multiple,
      'max_choices', p.max_choices,
      'allow_change_vote', p.allow_change_vote,
      'created_at', p.created_at,
      'options', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', po.id,
            'poll_id', po.poll_id,
            'text', po.text,
            'position', po.position
          )
          order by po.position asc
        )
        from public.poll_options po
        where po.poll_id = p.id
      ), '[]'::jsonb),
      'voted', exists (
        select 1
        from public.poll_votes pv
        where pv.poll_id = p.id
          and pv.user_id = (select id from dashboard_user)
      )
    )
    order by p.created_at desc
  ), '[]'::jsonb) as value
  from (
    select *
    from public.polls
    where visibility = 'public'
      and status = 'active'
    order by created_at desc
    limit 20
  ) p
)
select jsonb_build_object(
  'user', case
    when exists (select 1 from dashboard_user)
    then (select to_jsonb(x) from dashboard_user x limit 1)
    else null
  end,
  'application', (select to_jsonb(x) from dashboard_application x),
  'reports', (select value from dashboard_reports),
  'notifications', (select value from dashboard_notifications),
  'preferences', coalesce((select value from dashboard_preferences), null),
  'clan', (select to_jsonb(x) from dashboard_clan x),
  'membership', (select to_jsonb(x) from dashboard_membership x),
  'invitations', (select value from dashboard_invitations),
  'clanInvites', coalesce(public.participant_list_clan_invites(), '{"incoming":[],"outgoing":[]}'::jsonb),
  'stats', (select value from dashboard_stats),
  'achievements', (select value from dashboard_achievements),
  'polls', (select value from dashboard_polls)
);
$function$;

revoke execute on function public.participant_get_dashboard() from public, anon;
grant execute on function public.participant_get_dashboard() to authenticated;
grant execute on function public.participant_get_dashboard() to postgres;
