-- Correct season leaderboard aggregation limits: cap source rows before jsonb_agg.

create or replace function private.prisma_participant_get_season_leaderboard(p_user_id uuid,p_season_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  if not exists(select 1 from public.seasons s where s.id=p_season_id) then raise exception 'SEASON_NOT_FOUND'; end if;

  return jsonb_build_object(
    'players',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',x.id,'season_id',x.season_id,'user_id',x.user_id,'rating',x.rating,'points',x.points,'rank',x.rank,
        'minecraft_nickname',x.minecraft_nickname
      ) order by x.rank asc nulls last,x.points desc,x.id)
      from (
        select sr.id,sr.season_id,sr.user_id,sr.rating,sr.points,sr.rank,u.minecraft_nickname
        from public.season_ratings sr join public.users u on u.id=sr.user_id
        where sr.season_id=p_season_id and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
        order by sr.rank asc nulls last,sr.points desc,sr.id limit 100
      ) x
    ),'[]'::jsonb),
    'clans',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',x.id,'season_id',x.season_id,'clan_id',x.clan_id,'rating',x.rating,'points',x.points,'rank',x.rank,
        'name',x.name,'tag',x.tag
      ) order by x.rank asc nulls last,x.points desc,x.id)
      from (
        select scr.id,scr.season_id,scr.clan_id,scr.rating,scr.points,scr.rank,c.name,c.tag
        from public.season_clan_ratings scr join public.clans c on c.id=scr.clan_id
        where scr.season_id=p_season_id and c.deleted_at is null and c.status='active'
        order by scr.rank asc nulls last,scr.points desc,scr.id limit 50
      ) x
    ),'[]'::jsonb)
  );
end;
$function$;