alter table public.clan_wars drop constraint if exists clan_wars_status_check;
alter table public.clan_wars add constraint clan_wars_status_check
check (status = any (array['pending'::text,'scheduled'::text,'active'::text,'finished'::text,'cancelled'::text]));

create or replace function private.prisma_participant_create_clan_war(p_user_id uuid,p_target text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; target_clan_id uuid; war_id uuid; lock_key bigint;
actor_name text; actor_tag text; target_name text; target_tag text;
begin
  if p_user_id is null then raise exception 'USER_NOT_LINKED'; end if;
  if p_target is null or char_length(trim(p_target))<1 or char_length(trim(p_target))>64 then raise exception 'CLAN_NOT_FOUND'; end if;
  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active' and c.status='active' and c.deleted_at is null
  limit 1 for update;
  if actor_clan_id is null or actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  select c.id,c.name,c.tag into target_clan_id,target_name,target_tag
  from public.clans c
  where c.deleted_at is null and c.status='active' and c.id<>actor_clan_id
    and (lower(trim(c.tag))=lower(trim(p_target)) or lower(trim(c.name))=lower(trim(p_target)))
  order by case when lower(trim(c.tag))=lower(trim(p_target)) then 0 else 1 end limit 1;
  if target_clan_id is null then raise exception 'CLAN_NOT_FOUND'; end if;
  lock_key:=hashtextextended(least(actor_clan_id::text,target_clan_id::text)||':'||greatest(actor_clan_id::text,target_clan_id::text),2147483647);
  perform pg_advisory_xact_lock(lock_key);
  if exists(select 1 from public.clan_wars w where w.status in ('pending','scheduled','active')
    and ((w.clan_a=actor_clan_id and w.clan_b=target_clan_id) or (w.clan_a=target_clan_id and w.clan_b=actor_clan_id)
         or w.clan_a=actor_clan_id or w.clan_b=actor_clan_id))
  then raise exception 'WAR_ALREADY_ACTIVE'; end if;
  select name,tag into actor_name,actor_tag from public.clans where id=actor_clan_id;
  insert into public.clan_wars(clan_a,clan_b,status,scheduled_at,score_a,score_b)
  values(actor_clan_id,target_clan_id,'pending',null,0,0) returning id into war_id;
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data,status,available_at)
  select u.id,u.telegram_id,'telegram','CLAN','Новый вызов на войну',
    'Клан ['||coalesce(actor_tag,'—')||'] '||coalesce(actor_name,'Клан')||
    ' предлагает вашему клану войну. Откройте раздел клана, чтобы принять или отклонить вызов.',
    jsonb_build_object('war_id',war_id,'clan_id',actor_clan_id,'target_clan_id',target_clan_id,'source','clan_war_challenge'),
    'pending',now()
  from public.clan_members cm join public.users u on u.id=cm.user_id
  where cm.clan_id=target_clan_id and cm.status='active' and cm.role in ('owner','co_owner','officer')
    and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and not u.is_banned;
  return jsonb_build_object('success',true,'war_id',war_id,'status','pending','clan_a',actor_clan_id,'clan_b',target_clan_id,'target_clan',target_name,'target_tag',target_tag);
end;
$function$;

create or replace function private.prisma_participant_respond_clan_war(p_user_id uuid,p_war_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; war record; action text:=upper(trim(coalesce(p_action,'')));
opponent_clan_id uuid; actor_name text; actor_tag text;
begin
  if action not in ('ACCEPT','DECLINE') then raise exception 'INVALID_ACTION'; end if;
  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active' and c.status='active' and c.deleted_at is null
  limit 1 for update;
  if actor_clan_id is null or actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  select w.* into war from public.clan_wars w where w.id=p_war_id for update;
  if not found then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status<>'pending' then raise exception 'WAR_NOT_PENDING'; end if;
  if war.clan_b<>actor_clan_id then raise exception 'NO_CLAN_PERMISSION'; end if;
  opponent_clan_id:=war.clan_a;
  if action='DECLINE' then
    update public.clan_wars set status='cancelled',updated_at=now() where id=p_war_id;
  else
    update public.clan_wars set status='scheduled',scheduled_at=now(),updated_at=now() where id=p_war_id;
  end if;
  select name,tag into actor_name,actor_tag from public.clans where id=actor_clan_id;
  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
  select p_user_id,u.telegram_id,case when action='ACCEPT' then 'CLAN_WAR_ACCEPTED' else 'CLAN_WAR_DECLINED' end,'clan_war',p_war_id,
    jsonb_build_object('war_id',p_war_id,'status',case when action='ACCEPT' then 'scheduled' else 'cancelled' end,'actor_clan_id',actor_clan_id)
  from public.users u where u.id=p_user_id limit 1;
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data,status,available_at)
  select u.id,u.telegram_id,'telegram','CLAN',
    case when action='ACCEPT' then 'Вызов на войну принят' else 'Вызов на войну отклонён' end,
    case when action='ACCEPT'
      then 'Клан ['||coalesce(actor_tag,'—')||'] '||coalesce(actor_name,'Клан')||' принял вызов. Война готова к началу.'
      else 'Клан ['||coalesce(actor_tag,'—')||'] '||coalesce(actor_name,'Клан')||' отклонил вызов на войну.'
    end,
    jsonb_build_object('war_id',p_war_id,'status',case when action='ACCEPT' then 'scheduled' else 'cancelled' end,'source','clan_war_response'),
    'pending',now()
  from public.clan_members cm join public.users u on u.id=cm.user_id
  where cm.clan_id=opponent_clan_id and cm.status='active' and cm.role in ('owner','co_owner','officer')
    and u.deleted_at is null and u.status='ACCEPTED'::public.application_status and not u.is_banned;
  return jsonb_build_object('success',true,'war_id',p_war_id,'status',case when action='ACCEPT' then 'scheduled' else 'cancelled' end);
end;
$function$;

create or replace function private.prisma_participant_start_clan_war(p_user_id uuid,p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; war record; lock_key bigint;
begin
  select cm.clan_id,cm.role into actor_clan_id,actor_role from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active' limit 1 for update;
  if actor_clan_id is null or actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  select * into war from public.clan_wars where id=p_war_id for update;
  if not found then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status<>'scheduled' then raise exception 'WAR_NOT_SCHEDULED'; end if;
  if actor_clan_id<>war.clan_a and actor_clan_id<>war.clan_b then raise exception 'NO_CLAN_PERMISSION'; end if;
  lock_key:=hashtextextended(least(war.clan_a::text,war.clan_b::text)||':'||greatest(war.clan_a::text,war.clan_b::text),2147483647);
  perform pg_advisory_xact_lock(lock_key);
  update public.clan_wars set status='active',scheduled_at=coalesce(scheduled_at,now()) where id=p_war_id;
  insert into public.audit_logs(actor_user_id,action,target_type,target_id,new_data)
  values(p_user_id,'CLAN_WAR_STARTED','clan_war',p_war_id,jsonb_build_object('war_id',p_war_id,'status','active'));
  return jsonb_build_object('success',true,'war_id',p_war_id,'status','active');
end;
$function$;

create or replace function private.prisma_participant_finish_clan_war(p_user_id uuid,p_war_id uuid,p_score_a integer,p_score_b integer)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  actor_clan_id uuid;
  actor_role text;
  war record;
  clan_a_row record;
  clan_b_row record;
  winner uuid;
  actual_a numeric;
  expected_a numeric;
  delta_a integer;
  delta_b integer;
  lock_key bigint;
  actor_tg_id bigint;
begin
  if coalesce(p_score_a,0)<0 or coalesce(p_score_b,0)<0 then raise exception 'INVALID_SCORE'; end if;

  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active'
  limit 1 for update;
  if actor_clan_id is null or actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;

  select * into war from public.clan_wars where id=p_war_id for update;
  if not found then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status<>'active' then raise exception 'WAR_NOT_ACTIVE'; end if;
  if actor_clan_id<>war.clan_a and actor_clan_id<>war.clan_b then raise exception 'NO_CLAN_PERMISSION'; end if;

  lock_key:=hashtextextended(
    least(war.clan_a::text,war.clan_b::text)||':'||
    greatest(war.clan_a::text,war.clan_b::text),2147483647
  );
  perform pg_advisory_xact_lock(lock_key);

  winner:=case when p_score_a>p_score_b then war.clan_a when p_score_b>p_score_a then war.clan_b else null end;

  select c.id,c.name,c.tag,c.rating,c.wins,c.losses into clan_a_row
  from public.clans c where c.id=war.clan_a for update;
  select c.id,c.name,c.tag,c.rating,c.wins,c.losses into clan_b_row
  from public.clans c where c.id=war.clan_b for update;

  expected_a:=1.0/(1.0+power(10.0,((coalesce(clan_b_row.rating,1000)-coalesce(clan_a_row.rating,1000))/400.0)));
  actual_a:=case when p_score_a>p_score_b then 1.0 when p_score_a<p_score_b then 0.0 else 0.5 end;
  delta_a:=round(32.0*(actual_a-expected_a))::integer;
  delta_b:=-delta_a;

  update public.clan_wars
  set status='finished',winner_clan_id=winner,score_a=p_score_a,score_b=p_score_b,updated_at=now()
  where id=p_war_id;

  update public.clans
  set rating=greatest(0,coalesce(rating,1000)+delta_a),
      wins=wins+case when winner=war.clan_a then 1 else 0 end,
      losses=losses+case when winner=war.clan_b then 1 else 0 end,
      updated_at=now()
  where id=war.clan_a;

  update public.clans
  set rating=greatest(0,coalesce(rating,1000)+delta_b),
      wins=wins+case when winner=war.clan_b then 1 else 0 end,
      losses=losses+case when winner=war.clan_a then 1 else 0 end,
      updated_at=now()
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
  values(war.clan_a,p_user_id,'WAR_FINISHED',0,now()),
        (war.clan_b,p_user_id,'WAR_FINISHED',0,now());

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    u.id,u.telegram_id,'telegram','CLAN','Война завершена',
    'Война между кланами ['||coalesce(clan_a_row.tag,'—')||'] '||coalesce(clan_a_row.name,'Клан')||
      ' и ['||coalesce(clan_b_row.tag,'—')||'] '||coalesce(clan_b_row.name,'Клан')||
      ' завершена со счётом '||p_score_a||':'||p_score_b||'. '||
      case
        when winner is null then 'Ничья.'
        when cm.clan_id=winner then 'Ваш клан победил.'
        else 'Победил соперник.'
      end,
    jsonb_build_object(
      'war_id',p_war_id,'score_a',p_score_a,'score_b',p_score_b,
      'winner_clan_id',winner,'rating_delta_a',delta_a,'rating_delta_b',delta_b
    ),
    'pending',now()
  from public.clan_members cm
  join public.users u on u.id=cm.user_id
  where cm.clan_id in (war.clan_a,war.clan_b)
    and cm.status='active'
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned;

  return jsonb_build_object(
    'success',true,'war_id',p_war_id,'status','finished',
    'score_a',p_score_a,'score_b',p_score_b,'winner_clan_id',winner,
    'rating_delta_a',delta_a,'rating_delta_b',delta_b
  );
end;
$function$;

create or replace function private.prisma_participant_cancel_clan_war(p_user_id uuid,p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; war record;
begin
  select cm.clan_id,cm.role into actor_clan_id,actor_role from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active' limit 1 for update;
  if actor_clan_id is null then raise exception 'NO_CLAN_PERMISSION'; end if;
  select * into war from public.clan_wars where id=p_war_id for update;
  if not found then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status not in ('pending','scheduled','active') then raise exception 'WAR_NOT_ACTIVE'; end if;
  if war.clan_a<>actor_clan_id and war.clan_b<>actor_clan_id then raise exception 'NO_CLAN_PERMISSION'; end if;
  if war.status='pending' and actor_clan_id=war.clan_b then raise exception 'USE_DECLINE'; end if;
  if actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  update public.clan_wars set status='cancelled',updated_at=now() where id=p_war_id;
  insert into public.audit_logs(actor_user_id,action,target_type,target_id,new_data)
  values(p_user_id,'CLAN_WAR_CANCELLED','clan_war',p_war_id,jsonb_build_object('status','cancelled'));
  return jsonb_build_object('success',true,'war_id',p_war_id,'status','cancelled');
end;
$function$;

create or replace function public.participant_respond_clan_war(p_war_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_respond_clan_war(uid,p_war_id,p_action);
end;
$function$;

create or replace function public.participant_start_clan_war(p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_start_clan_war(uid,p_war_id);
end;
$function$;

create or replace function public.participant_finish_clan_war(p_war_id uuid,p_score_a integer,p_score_b integer)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_finish_clan_war(uid,p_war_id,p_score_a,p_score_b);
end;
$function$;

revoke execute on function public.participant_respond_clan_war(uuid,text) from public,anon;
grant execute on function public.participant_respond_clan_war(uuid,text) to authenticated;
revoke execute on function public.participant_start_clan_war(uuid) from public,anon;
grant execute on function public.participant_start_clan_war(uuid) to authenticated;
revoke execute on function public.participant_finish_clan_war(uuid,integer,integer) from public,anon;
grant execute on function public.participant_finish_clan_war(uuid,integer,integer) to authenticated;