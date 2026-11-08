-- Return one participant's exact rank/value without loading a full leaderboard.

create or replace function private.prisma_participant_get_ranking_entry(p_user_id uuid,p_category text default 'rating')
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  category text:=lower(coalesce(p_category,'rating'));
  target_value numeric;
  target_nickname text;
  target_rating integer;
  target_activity integer;
  target_level integer;
  target_xp bigint;
  target_kills bigint;
  target_deaths bigint;
  target_playtime bigint;
  target_blocks bigint;
  target_blocks_placed bigint;
  target_damage numeric;
  target_damage_taken numeric;
  target_distance numeric;
  target_mobs bigint;
  target_achievements bigint;
  rank_value bigint;
begin
  perform private.prisma_participant_require_access(p_user_id);

  if category not in ('rating','kills','deaths','kdr','playtime','blocks','blocks_placed','damage','damage_taken','distance','mobs','achievements','activity','level','xp') then
    category:='rating';
  end if;

  select
    u.minecraft_nickname,u.rating,u.activity_score,u.level,u.xp,
    coalesce(ps.kills,0),coalesce(ps.deaths,0),coalesce(ps.playtime_minutes,0),
    coalesce(ps.blocks_broken,0),coalesce(ps.blocks_placed,0),
    coalesce(ps.damage_dealt,0),coalesce(ps.damage_taken,0),
    coalesce(ps.distance_walked,0),coalesce(ps.mobs_killed,0),
    (select count(*) from public.user_achievements ua where ua.user_id=u.id)
  into target_nickname,target_rating,target_activity,target_level,target_xp,
       target_kills,target_deaths,target_playtime,target_blocks,target_blocks_placed,
       target_damage,target_damage_taken,target_distance,target_mobs,target_achievements
  from public.users u
  left join public.player_stats ps on ps.user_id=u.id
  where u.id=p_user_id and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
    and u.minecraft_nickname is not null;

  if target_nickname is null then return null; end if;

  target_value:=case
    when category='kills' then target_kills
    when category='deaths' then target_deaths
    when category='kdr' then case when target_deaths>0 then target_kills::numeric/target_deaths else target_kills end
    when category='playtime' then target_playtime
    when category='blocks' then target_blocks
    when category='blocks_placed' then target_blocks_placed
    when category='damage' then target_damage
    when category='damage_taken' then target_damage_taken
    when category='distance' then target_distance
    when category='mobs' then target_mobs
    when category='achievements' then target_achievements
    when category='activity' then target_activity
    when category='level' then target_level
    when category='xp' then target_xp
    else target_rating
  end;

  with base as (
    select u.id,
      case
        when category='kills' then coalesce(ps.kills,0)
        when category='deaths' then coalesce(ps.deaths,0)
        when category='kdr' then case when coalesce(ps.deaths,0)>0 then coalesce(ps.kills,0)::numeric/coalesce(ps.deaths,0) else coalesce(ps.kills,0) end
        when category='playtime' then coalesce(ps.playtime_minutes,0)
        when category='blocks' then coalesce(ps.blocks_broken,0)
        when category='blocks_placed' then coalesce(ps.blocks_placed,0)
        when category='damage' then coalesce(ps.damage_dealt,0)
        when category='damage_taken' then coalesce(ps.damage_taken,0)
        when category='distance' then coalesce(ps.distance_walked,0)
        when category='mobs' then coalesce(ps.mobs_killed,0)
        when category='achievements' then (select count(*) from public.user_achievements ua where ua.user_id=u.id)
        when category='activity' then coalesce(u.activity_score,0)
        when category='level' then coalesce(u.level,1)
        when category='xp' then coalesce(u.xp,0)
        else coalesce(u.rating,0)
      end::numeric as value
    from public.users u
    left join public.player_stats ps on ps.user_id=u.id
    where u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned and u.minecraft_nickname is not null
  )
  select 1+count(*) into rank_value
  from base b
  where b.value>target_value or (b.value=target_value and b.id<p_user_id);

  return jsonb_build_object(
    'id',p_user_id,'minecraft_nickname',target_nickname,'rating',target_rating,
    'activity_score',target_activity,'level',target_level,'xp',target_xp,
    'value',target_value,'rank',rank_value
  );
end;
$function$;

create or replace function public.participant_get_ranking_entry(p_category text default 'rating')
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_ranking_entry(uid,p_category);
end;
$function$;

revoke all on function public.participant_get_ranking_entry(text) from public,anon;
grant execute on function public.participant_get_ranking_entry(text) to authenticated;
