CREATE OR REPLACE FUNCTION private.prisma_participant_start_battle(
  p_user_id uuid,
  p_opponent_nickname text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  me public.users%rowtype;
  opponent public.users%rowtype;
  a public.player_stats%rowtype;
  b public.player_stats%rowtype;
  my_achievements integer:=0;
  opponent_achievements integer:=0;
  my_score integer:=0;
  opponent_score integer:=0;
  winner uuid;
  points integer:=0;
  battle_id uuid;
  previous_battle_id uuid;
  my_new_rating integer;
  opponent_new_rating integer;
  opponent_id uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select u.id into opponent_id
  from public.users u
  where lower(trim(u.minecraft_nickname))=lower(trim(p_opponent_nickname))
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned
    and u.is_whitelisted
  limit 1;

  if opponent_id is null or opponent_id=p_user_id
     or coalesce(trim(p_opponent_nickname),'')=''
     or char_length(trim(p_opponent_nickname))>16 then
    raise exception 'OPPONENT_NOT_FOUND';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      least(p_user_id::text,opponent_id::text)||':'||
      greatest(p_user_id::text,opponent_id::text),
      0
    )
  );

  select u.* into me from public.users u where u.id=p_user_id for update;
  select u.* into opponent from public.users u where u.id=opponent_id for update;

  if me.id is null or opponent.id is null
     or me.deleted_at is not null or opponent.deleted_at is not null
     or me.status<>'ACCEPTED'::public.application_status
     or opponent.status<>'ACCEPTED'::public.application_status
     or me.is_banned or opponent.is_banned
     or not me.is_whitelisted or not opponent.is_whitelisted then
    raise exception 'OPPONENT_NOT_FOUND';
  end if;

  if char_length(trim(p_opponent_nickname))>16 then
    raise exception 'OPPONENT_INVALID';
  end if;

  select pb.id into previous_battle_id
  from public.player_battles pb
  where (
    (pb.challenger_id=me.id and pb.opponent_id=opponent.id)
    or
    (pb.challenger_id=opponent.id and pb.opponent_id=me.id)
  )
    and pb.created_at>=now()-interval '24 hours'
  order by pb.created_at desc
  limit 1;

  if previous_battle_id is not null then raise exception 'BATTLE_COOLDOWN'; end if;

  select * into a from public.player_stats where user_id=me.id;
  select * into b from public.player_stats where user_id=opponent.id;

  select count(*)::integer into my_achievements
  from public.user_achievements where user_id=me.id;
  select count(*)::integer into opponent_achievements
  from public.user_achievements where user_id=opponent.id;

  if coalesce(a.kills,0)>coalesce(b.kills,0) then my_score:=my_score+1;
  elsif coalesce(b.kills,0)>coalesce(a.kills,0) then opponent_score:=opponent_score+1; end if;

  if coalesce(a.deaths,0)<coalesce(b.deaths,0) then my_score:=my_score+1;
  elsif coalesce(b.deaths,0)<coalesce(a.deaths,0) then opponent_score:=opponent_score+1; end if;

  if coalesce(a.playtime_minutes,0)>coalesce(b.playtime_minutes,0) then my_score:=my_score+1;
  elsif coalesce(b.playtime_minutes,0)>coalesce(a.playtime_minutes,0) then opponent_score:=opponent_score+1; end if;

  if coalesce(a.blocks_broken,0)>coalesce(b.blocks_broken,0) then my_score:=my_score+1;
  elsif coalesce(b.blocks_broken,0)>coalesce(a.blocks_broken,0) then opponent_score:=opponent_score+1; end if;

  if my_achievements>opponent_achievements then my_score:=my_score+1;
  elsif opponent_achievements>my_achievements then opponent_score:=opponent_score+1; end if;

  if my_score>opponent_score then winner:=me.id; points:=10;
  elsif opponent_score>my_score then winner:=opponent.id; points:=10;
  else winner:=null; end if;

  my_new_rating:=me.rating;
  opponent_new_rating:=opponent.rating;

  if winner is not null then
    if winner=me.id then
      my_new_rating:=me.rating+points;
      opponent_new_rating:=greatest(0,opponent.rating-points);
    else
      opponent_new_rating:=opponent.rating+points;
      my_new_rating:=greatest(0,me.rating-points);
    end if;
  end if;

  insert into public.player_battles(
    challenger_id,opponent_id,challenger_score,opponent_score,winner_id,points_awarded,status
  ) values(me.id,opponent.id,my_score,opponent_score,winner,points,'COMPLETED')
  returning id into battle_id;

  if winner is not null then
    update public.users set rating=my_new_rating,updated_at=now() where id=me.id;
    update public.users set rating=opponent_new_rating,updated_at=now() where id=opponent.id;
    insert into public.rating_history(user_id,rating,delta,reason)
    values
      (me.id,my_new_rating,my_new_rating-me.rating,'Player Battle'),
      (opponent.id,opponent_new_rating,opponent_new_rating-opponent.rating,'Player Battle');
  end if;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select me.id,me.telegram_id,'telegram','BATTLE',
    case when winner=me.id then 'Вы выиграли Player Battle'
         when winner=opponent.id then 'Вы проиграли Player Battle'
         else 'Ничья в Player Battle' end,
    'Результат: '||my_score||' : '||opponent_score||'.',
    jsonb_build_object('battle_id',battle_id,'opponent',opponent.minecraft_nickname,
      'score',my_score||':'||opponent_score,
      'points',case when winner=me.id then points when winner=opponent.id then -points else 0 end,
      'source','player_battle')
  where me.telegram_id is not null;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select opponent.id,opponent.telegram_id,'telegram','BATTLE',
    case when winner=opponent.id then 'Вы выиграли Player Battle'
         when winner=me.id then 'Вы проиграли Player Battle'
         else 'Ничья в Player Battle' end,
    'Результат: '||opponent_score||' : '||my_score||'.',
    jsonb_build_object('battle_id',battle_id,'opponent',me.minecraft_nickname,
      'score',opponent_score||':'||my_score,
      'points',case when winner=opponent.id then points when winner=me.id then -points else 0 end,
      'source','player_battle')
  where opponent.telegram_id is not null;

  return jsonb_build_object(
    'success',true,'battle_id',battle_id,
    'challenger_score',my_score,'opponent_score',opponent_score,
    'winner_id',winner,'points_awarded',points,
    'challenger_rating',my_new_rating,'opponent_rating',opponent_new_rating
  );
end;
$function$;