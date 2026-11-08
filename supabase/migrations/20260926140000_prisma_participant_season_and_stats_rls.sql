-- Season leaderboard gateway and participant-only RLS for game statistics.

create or replace function private.prisma_participant_get_season_leaderboard(p_user_id uuid,p_season_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  if not exists(select 1 from public.seasons s where s.id=p_season_id) then raise exception 'SEASON_NOT_FOUND'; end if;

  return jsonb_build_object(
    'players',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',sr.id,'season_id',sr.season_id,'user_id',sr.user_id,'rating',sr.rating,'points',sr.points,'rank',sr.rank,
        'minecraft_nickname',u.minecraft_nickname
      ) order by sr.rank asc nulls last,sr.points desc,sr.id)
      from public.season_ratings sr
      join public.users u on u.id=sr.user_id
      where sr.season_id=p_season_id and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
      limit 100
    ),'[]'::jsonb),
    'clans',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',scr.id,'season_id',scr.season_id,'clan_id',scr.clan_id,'rating',scr.rating,'points',scr.points,'rank',scr.rank,
        'name',c.name,'tag',c.tag
      ) order by scr.rank asc nulls last,scr.points desc,scr.id)
      from public.season_clan_ratings scr
      join public.clans c on c.id=scr.clan_id
      where scr.season_id=p_season_id and c.deleted_at is null and c.status='active'
      limit 50
    ),'[]'::jsonb)
  );
end;
$function$;

create or replace function public.participant_get_season_leaderboard(p_season_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_season_leaderboard(uid,p_season_id);
end;
$function$;

revoke all on function public.participant_get_season_leaderboard(uuid) from public,anon;
grant execute on function public.participant_get_season_leaderboard(uuid) to authenticated;

drop policy if exists player_stats_member_select on public.player_stats;
drop policy if exists player_stats_owner_or_staff_select on public.player_stats;
create policy player_stats_owner_or_staff_select on public.player_stats
for select to authenticated
using (
  exists(select 1 from public.users u where u.id=player_stats.user_id and u.auth_user_id=(select auth.uid()))
  or (select private.has_permission('player.view'))
);

drop policy if exists user_achievements_staff_read on public.user_achievements;
drop policy if exists user_achievements_owner_or_staff_select on public.user_achievements;
create policy user_achievements_owner_or_staff_select on public.user_achievements
for select to authenticated
using (
  exists(select 1 from public.users u where u.id=user_achievements.user_id and u.auth_user_id=(select auth.uid()))
  or (select private.has_permission('player.view'))
);

drop policy if exists rating_history_member_select on public.rating_history;
drop policy if exists rating_history_owner_or_staff_select on public.rating_history;
create policy rating_history_owner_or_staff_select on public.rating_history
for select to authenticated
using (
  exists(select 1 from public.users u where u.id=rating_history.user_id and u.auth_user_id=(select auth.uid()))
  or (select private.has_permission('player.view'))
);
