create or replace function private.prisma_participant_finish_clan_war(p_user_id uuid,p_war_id uuid,p_score_a integer,p_score_b integer)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; war record; clan_a_row record; clan_b_row record;
winner uuid; actual_a numeric; expected_a numeric; delta_a integer; delta_b integer; lock_key bigint; actor_tg_id bigint;
begin
  if coalesce(p_score_a,0)<0 or coalesce(p_score_b,0)<0 then raise exception 'INVALID_SCORE'; end if;
  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active' limit 1 for update;
  if actor_clan_id is null or actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  select * into war from public.clan_wars where id=p_war_id for update;
  if not found then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status<>'active' then raise exception 'WAR_NOT_ACTIVE'; end if;
  if actor_clan_id<>war.clan_a and actor_clan_id<>war.clan_b then raise exception 'NO_CLAN_PERMISSION'; end if;
  lock_key:=hashtextextended(least(war.clan_a::text,war.clan_b::text)||':'||greatest(war.clan_a::text,war.clan_b::text),2147483647);
  perform pg_advisory_xact_lock(lock_key);
  winner:=case when p_score_a>p_score_b then war.clan_a when p_score_b>p_score_a then war.clan_b else null end;
  select c.id,c.name,c.tag,c.rating,c.wins,c.losses into clan_a_row from public.clans c where c.id=war.clan_a for update;
  select c.id,c.name,c.tag,c.rating,c.wins,c.losses into clan_b_row from public.clans c where c.id=war.clan_b for update;
  expected_a:=1.0/(1.0+power(10.0,((coalesce(clan_b_row.rating,1000)-coalesce(clan_a_row.rating,1000))/400.0)));
  actual_a:=case when p_score_a>p_score_b then 1.0 when p_score_a<p_score_b then 0.0 else 0.5 end;
  delta_a:=round(32.0*(actual_a-expected_a))::integer;
  delta_b:=-delta_a;
  update public.clan_wars
  set status='finished',winner_clan_id=winner,score_a=p_score_a,score_b=p_score_b
  where id=p_war_id;
  update public.clans
  set rating=greatest(0,coalesce(rating,1000)+delta_a),
      wins=wins+case when winner=war.clan_a then 1 else 0 end,
      losses=losses+case when winner=war.clan_b then 1 else 0 end,updated_at=now()
  where id=war.clan_a;
  update public.clans
  set rating=greatest(0,coalesce(rating,1000)+delta_b),
      wins=wins+case when winner=war.clan_b then 1 else 0 end,
      losses=losses+case when winner=war.clan_a then 1 else 0 end,updated_at=now()
  where id=war.clan_b;
  select telegram_id into actor_tg_id from public.users where id=p_user_id;
  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
  values(
    p_user_id,actor_tg_id,'CLAN_WAR_FINISHED','clan_war',p_war_id,
    jsonb_build_object('status','active','score_a',war.score_a,'score_b',war.score_b),
    jsonb_build_object('status','finished','score_a',p_score_a,'score_b',p_score_b,
      'winner_clan_id',winner,'rating_delta_a',delta_a,'rating_delta_b',delta_b)
  );
  insert into public.clan_activity(clan_id,user_id,kind,xp,created_at)
  values(war.clan_a,p_user_id,'WAR_FINISHED',0,now()),(war.clan_b,p_user_id,'WAR_FINISHED',0,now());
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data,status,available_at)
  select u.id,u.telegram_id,'telegram','CLAN','Война завершена',
    'Война между кланами ['||coalesce(clan_a_row.tag,'—')||'] '||coalesce(clan_a_row.name,'Клан')||
    ' и ['||coalesce(clan_b_row.tag,'—')||'] '||coalesce(clan_b_row.name,'Клан')||
    ' завершена со счётом '||p_score_a||':'||p_score_b||'. '||
    case when winner is null then 'Ничья.'
         when cm.clan_id=winner then 'Ваш клан победил.'
         else 'Победил соперник.'
    end,
    jsonb_build_object('war_id',p_war_id,'score_a',p_score_a,'score_b',p_score_b,
      'winner_clan_id',winner,'rating_delta_a',delta_a,'rating_delta_b',delta_b),
    'pending',now()
  from public.clan_members cm join public.users u on u.id=cm.user_id
  where cm.clan_id in (war.clan_a,war.clan_b) and cm.status='active'
    and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and not u.is_banned;
  return jsonb_build_object('success',true,'war_id',p_war_id,'status','finished',
    'score_a',p_score_a,'score_b',p_score_b,'winner_clan_id',winner,
    'rating_delta_a',delta_a,'rating_delta_b',delta_b);
end;
$function$;