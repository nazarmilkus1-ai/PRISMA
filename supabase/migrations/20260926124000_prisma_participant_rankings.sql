-- Safe participant rankings gateway. Browser clients never read the full users/statistics sets directly.

create or replace function private.prisma_participant_get_rankings(p_user_id uuid,p_category text default 'rating',p_limit integer default 100)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare category text:=lower(coalesce(p_category,'rating'));
begin
  perform private.prisma_participant_require_access(p_user_id);
  if category not in ('rating','kills','deaths','kdr','playtime','blocks','blocks_placed','damage','damage_taken','distance','mobs','achievements','activity','level','xp') then
    category:='rating';
  end if;

  return coalesce((
    with base as (
      select u.id,u.minecraft_nickname,u.rating,u.activity_score,u.level,u.xp,u.clan_id,
             coalesce(ps.kills,0) kills,coalesce(ps.deaths,0) deaths,
             coalesce(ps.playtime_minutes,0) playtime_minutes,
             coalesce(ps.blocks_broken,0) blocks_broken,coalesce(ps.blocks_placed,0) blocks_placed,
             coalesce(ps.damage_dealt,0) damage_dealt,coalesce(ps.damage_taken,0) damage_taken,
             coalesce(ps.distance_walked,0) distance_walked,coalesce(ps.mobs_killed,0) mobs_killed,
             (select count(*) from public.user_achievements ua where ua.user_id=u.id) achievements
      from public.users u
      left join public.player_stats ps on ps.user_id=u.id
      where u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
        and u.minecraft_nickname is not null
    ),
    scored as (
      select b.*,
        case
          when category='kills' then b.kills
          when category='deaths' then b.deaths
          when category='kdr' then case when b.deaths>0 then b.kills::numeric/b.deaths else b.kills end
          when category='playtime' then b.playtime_minutes
          when category='blocks' then b.blocks_broken
          when category='blocks_placed' then b.blocks_placed
          when category='damage' then b.damage_dealt
          when category='damage_taken' then b.damage_taken
          when category='distance' then b.distance_walked
          when category='mobs' then b.mobs_killed
          when category='achievements' then b.achievements
          when category='activity' then b.activity_score
          when category='level' then b.level
          when category='xp' then b.xp
          else b.rating
        end as value
      from base b
    ),
    ranked as (
      select s.*,row_number() over(order by s.value desc,s.id asc) as rank
      from scored s
    ),
    limited as (
      select * from ranked
      order by rank
      limit greatest(1,least(coalesce(p_limit,100),300))
    )
    select jsonb_agg(jsonb_build_object(
      'id',id,'minecraft_nickname',minecraft_nickname,'rating',rating,
      'activity_score',activity_score,'level',level,'xp',xp,'clan_id',clan_id,
      'value',value,'achievements',achievements,'rank',rank
    ) order by rank)
    from limited
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_get_rankings(p_category text default 'rating',p_limit integer default 100)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_rankings(uid,p_category,p_limit);
end;
$function$;

revoke all on function public.participant_get_rankings(text,integer) from public,anon;
grant execute on function public.participant_get_rankings(text,integer) to authenticated;
