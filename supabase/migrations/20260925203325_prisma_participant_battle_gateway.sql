-- Atomic Player Battle transaction and authenticated gateway.

create or replace function private.prisma_participant_start_battle(
  p_user_id uuid,p_opponent_nickname text
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  challenger record; opponent record; recent_count integer;
  challenger_score bigint:=0; opponent_score bigint:=0; winner uuid; points integer:=0;
  challenger_rating integer; opponent_rating integer;
  challenger_new_rating integer; opponent_new_rating integer;
  battle_id uuid; lock_key bigint;
  ck bigint:=0; cd bigint:=0; cp bigint:=0; cb bigint:=0;
  ok bigint:=0; od bigint:=0; op bigint:=0; ob bigint:=0;
  ca bigint:=0; oa bigint:=0;
begin
  if p_user_id is null then raise exception 'USER_NOT_LINKED'; end if;
  if p_opponent_nickname is null or char_length(trim(p_opponent_nickname)) not between 3 and 17
    then raise exception 'OPPONENT_INVALID'; end if;

  select u.id,u.minecraft_nickname,u.rating into challenger
  from public.users u
  where u.id=p_user_id and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status and not u.is_banned
  for update;
  if challenger.id is null then raise exception 'USER_NOT_APPROVED'; end if;

  select u.id,u.minecraft_nickname,u.rating into opponent
  from public.users u
  where u.deleted_at is null and u.status='ACCEPTED'::public.application_status
    and not u.is_banned and u.id<>p_user_id
    and (
      lower(trim(u.minecraft_nickname))=lower(trim(p_opponent_nickname))
      or lower(trim(u.minecraft_nickname))=lower(trim('.'||trim(p_opponent_nickname)))
    )
  limit 1 for update;
  if opponent.id is null then raise exception 'OPPONENT_NOT_FOUND'; end if;

  lock_key:=hashtextextended(
    least(challenger.id::text,opponent.id::text)||':'||
    greatest(challenger.id::text,opponent.id::text),2147483647
  );
  perform pg_advisory_xact_lock(lock_key);

  select count(*) into recent_count from public.player_battles b
  where b.created_at>=now()-interval '24 hours'
    and (
      (b.challenger_id=challenger.id and b.opponent_id=opponent.id)
      or (b.challenger_id=opponent.id and b.opponent_id=challenger.id)
    );
  if recent_count>0 then raise exception 'BATTLE_COOLDOWN'; end if;

  select coalesce(s.kills,0),coalesce(s.deaths,0),
         coalesce(s.playtime_minutes,0),coalesce(s.blocks_broken,0)
    into ck,cd,cp,cb
  from public.player_stats s where s.user_id=challenger.id;

  select coalesce(s.kills,0),coalesce(s.deaths,0),
         coalesce(s.playtime_minutes,0),coalesce(s.blocks_broken,0)
    into ok,od,op,ob
  from public.player_stats s where s.user_id=opponent.id;

  select count(*) into ca from public.user_achievements where user_id=challenger.id;
  select count(*) into oa from public.user_achievements where user_id=opponent.id;

  if ck>ok then challenger_score:=challenger_score+1; elsif ok>ck then opponent_score:=opponent_score+1; end if;
  if cd<od then challenger_score:=challenger_score+1; elsif od<cd then opponent_score:=opponent_score+1; end if;
  if cp>op then challenger_score:=challenger_score+1; elsif op>cp then opponent_score:=opponent_score+1; end if;
  if cb>ob then challenger_score:=challenger_score+1; elsif ob>cb then opponent_score:=opponent_score+1; end if;
  if ca>oa then challenger_score:=challenger_score+1; elsif oa>ca then opponent_score:=opponent_score+1; end if;

  if challenger_score>opponent_score then winner:=challenger.id;
  elsif opponent_score>challenger_score then winner:=opponent.id;
  else winner:=null; end if;

  if winner is not null then points:=10; end if;

  challenger_rating:=coalesce(challenger.rating,0);
  opponent_rating:=coalesce(opponent.rating,0);
  challenger_new_rating:=case
    when winner=challenger.id then challenger_rating+points
    when winner=opponent.id then greatest(0,challenger_rating-points)
    else challenger_rating end;
  opponent_new_rating:=case
    when winner=opponent.id then opponent_rating+points
    when winner=challenger.id then greatest(0,opponent_rating-points)
    else opponent_rating end;

  insert into public.player_battles(
    challenger_id,opponent_id,challenger_score,opponent_score,
    winner_id,points_awarded,status
  ) values(
    challenger.id,opponent.id,challenger_score,opponent_score,winner,points,'COMPLETED'
  ) returning id into battle_id;

  update public.users set rating=challenger_new_rating,updated_at=now() where id=challenger.id;
  update public.users set rating=opponent_new_rating,updated_at=now() where id=opponent.id;

  if winner is not null then
    insert into public.rating_history(user_id,rating,delta,reason)
    values
      (challenger.id,challenger_new_rating,challenger_new_rating-challenger_rating,'Player Battle'),
      (opponent.id,opponent_new_rating,opponent_new_rating-opponent_rating,'Player Battle');
  end if;

  return jsonb_build_object(
    'success',true,'battle_id',battle_id,
    'challenger_score',challenger_score,'opponent_score',opponent_score,
    'winner_id',winner,'points_awarded',points
  );
end;
$function$;

create or replace function public.participant_start_battle(p_opponent_nickname text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_start_battle(uid,p_opponent_nickname);
end;
$function$;

revoke all on function public.participant_start_battle(text) from public,anon;
grant execute on function public.participant_start_battle(text) to authenticated;
revoke all on function private.prisma_participant_start_battle(uuid,text) from public,anon,authenticated;
