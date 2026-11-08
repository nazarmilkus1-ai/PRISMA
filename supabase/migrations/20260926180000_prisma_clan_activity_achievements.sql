create schema if not exists private;

-- Canonical clan activity writer.
create or replace function private.prisma_clan_record_activity(
  p_clan_id uuid,
  p_user_id uuid default null,
  p_kind text default 'CLAN_ACTIVITY',
  p_xp integer default 0,
  p_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_id bigint;
begin
  if p_clan_id is null then
    return null;
  end if;

  insert into public.clan_activity(clan_id,user_id,kind,xp,payload,created_at)
  values(p_clan_id,p_user_id,p_kind,coalesce(p_xp,0),coalesce(p_payload,'{}'::jsonb),now())
  returning id into v_id;

  return v_id;
end;
$function$;

-- Automatic clan achievements. coin_reward is always zero: PRISMA does not use a custom currency.
create or replace function private.prisma_clan_unlock_achievements(
  p_clan_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  a record;
  v_members integer;
  v_villages integer;
  v_wins integer;
  v_activity integer;
  v_clan_name text;
begin
  select c.name,c.wins into v_clan_name,v_wins
  from public.clans c
  where c.id=p_clan_id
    and c.status='active'
    and c.deleted_at is null;

  if v_clan_name is null then
    return;
  end if;

  select count(*)::integer into v_members
  from public.clan_members cm
  where cm.clan_id=p_clan_id and cm.status='active';

  select count(*)::integer into v_villages
  from public.clan_villages cv
  where cv.clan_id=p_clan_id and cv.status='active';

  select count(*)::integer into v_activity
  from public.clan_activity ca
  where ca.clan_id=p_clan_id;

  for a in
    select id,code,title,description,icon,xp_reward
    from public.achievements
    where
      (code='CLAN_FOUNDER' and v_members>=1)
      or (code='CLAN_FIVE' and v_members>=5)
      or (code='CLAN_TEN' and v_members>=10)
      or (code='CLAN_TERRITORY_MASTER' and v_villages>=3)
      or (code='CLAN_FIRST_WIN' and coalesce(v_wins,0)>=1)
      or (code='CLAN_VETERAN' and v_activity>=25)
  loop
    insert into public.clan_achievements(clan_id,achievement_id,unlocked_at)
    values(p_clan_id,a.id,now())
    on conflict (clan_id,achievement_id) do nothing;

    if found then
      insert into public.notifications(
        user_id,telegram_id,channel,kind,title,body,data,status,available_at
      )
      select
        cm.user_id,
        u.telegram_id,
        'telegram',
        'CLAN',
        'Новое достижение клана',
        'Клан "'||v_clan_name||'" открыл достижение "'||a.title||'".',
        jsonb_build_object(
          'clan_id',p_clan_id,
          'achievement_id',a.id,
          'code',a.code,
          'xp_reward',a.xp_reward,
          'source','clan_achievement'
        ),
        'pending',
        now()
      from public.clan_members cm
      join public.users u on u.id=cm.user_id
      where cm.clan_id=p_clan_id
        and cm.status='active'
        and u.deleted_at is null
        and u.status='ACCEPTED'::public.application_status
        and not u.is_banned;
    end if;
  end loop;
end;
$function$;

insert into public.achievements(code,title,description,icon,xp_reward,coin_reward)
values
  ('CLAN_FOUNDER','Основание','Клан создан и собрал первый активный состав.','🏴',50,0),
  ('CLAN_FIVE','Пять участников','В клане одновременно состоит 5 активных участников.','👥',100,0),
  ('CLAN_TEN','Десять участников','В клане одновременно состоит 10 активных участников.','🏰',200,0),
  ('CLAN_TERRITORY_MASTER','Территориальная сеть','Клан имеет 3 активные территории.','🗺️',150,0),
  ('CLAN_FIRST_WIN','Первая победа','Клан одержал первую победу в войне.','⚔️',200,0),
  ('CLAN_VETERAN','Старая гвардия','В истории клана накопилось 25 активностей.','📜',250,0)
on conflict(code) do update set
  title=excluded.title,
  description=excluded.description,
  icon=excluded.icon,
  xp_reward=excluded.xp_reward,
  coin_reward=0;

-- One trigger translates domain changes into a shared clan history.
create or replace function private.prisma_clan_entity_activity()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_kind text;
  v_clan_id uuid;
  v_user_id uuid;
  v_payload jsonb := '{}'::jsonb;
begin
  if tg_table_name='clan_members' then
    v_clan_id := case when tg_op='DELETE' then old.clan_id else new.clan_id end;
    v_user_id := case when tg_op='DELETE' then old.user_id else new.user_id end;

    if tg_op='INSERT' and new.status='active' then
      if new.role='owner'
         and not exists(
           select 1 from public.clan_members cm
           where cm.clan_id=new.clan_id
             and cm.user_id<>new.user_id
             and cm.status='active'
         )
      then
        v_kind := 'CLAN_CREATED';
      else
        v_kind := 'MEMBER_JOIN';
      end if;
      v_payload := jsonb_build_object('role',new.role);
    elsif tg_op='UPDATE' and old.status='active' and new.status<>'active' then
      v_kind := 'MEMBER_LEAVE';
      v_payload := jsonb_build_object('role',old.role);
    elsif tg_op='UPDATE' and old.role is distinct from new.role then
      v_kind := 'ROLE_CHANGE';
      v_payload := jsonb_build_object('old_role',old.role,'role',new.role);
    elsif tg_op='UPDATE' and old.clan_id is distinct from new.clan_id then
      v_kind := 'MEMBER_MOVED';
      v_payload := jsonb_build_object('from_clan_id',old.clan_id,'to_clan_id',new.clan_id);
    end if;

    if v_kind is not null and v_clan_id is not null then
      perform private.prisma_clan_record_activity(v_clan_id,v_user_id,v_kind,0,v_payload);
    end if;

  elsif tg_table_name='clan_invitations' then
    v_clan_id := case when tg_op='DELETE' then old.clan_id else new.clan_id end;

    if tg_op='INSERT' then
      v_kind := 'INVITE_SENT';
      v_user_id := new.inviter_id;
      v_payload := jsonb_build_object('invite_id',new.id,'invitee_id',new.invitee_id);
    elsif tg_op='UPDATE' and old.status is distinct from new.status then
      v_user_id := new.invitee_id;
      v_kind := case new.status
        when 'accepted' then 'INVITE_ACCEPTED'
        when 'declined' then 'INVITE_DECLINED'
        when 'cancelled' then 'INVITE_CANCELLED'
        when 'expired' then 'INVITE_EXPIRED'
        else 'INVITE_UPDATED'
      end;
      v_payload := jsonb_build_object('invite_id',new.id,'status',new.status,'inviter_id',new.inviter_id);
    end if;

    if v_kind is not null and v_clan_id is not null then
      perform private.prisma_clan_record_activity(v_clan_id,v_user_id,v_kind,0,v_payload);
    end if;

  elsif tg_table_name='clan_announcements' then
    v_clan_id := case when tg_op='DELETE' then old.clan_id else new.clan_id end;
    v_user_id := case when tg_op='DELETE' then old.author_id else new.author_id end;

    if tg_op='INSERT' then
      v_kind := 'ANNOUNCEMENT_CREATED';
      v_payload := jsonb_build_object('announcement_id',new.id,'title',new.title);
    elsif tg_op='DELETE' then
      v_kind := 'ANNOUNCEMENT_DELETED';
      v_payload := jsonb_build_object('announcement_id',old.id,'title',old.title);
    end if;

    if v_kind is not null and v_clan_id is not null then
      perform private.prisma_clan_record_activity(v_clan_id,v_user_id,v_kind,0,v_payload);
    end if;

  elsif tg_table_name='clan_villages' then
    v_clan_id := case when tg_op='DELETE' then old.clan_id else new.clan_id end;
    v_user_id := case when tg_op='DELETE' then old.created_by else new.created_by end;

    if tg_op='INSERT' and new.status='active' then
      v_kind := 'VILLAGE_CREATED';
      v_payload := jsonb_build_object(
        'village_id',new.id,
        'name',new.name,
        'world',new.world,
        'x',new.center_x,
        'z',new.center_z,
        'radius',new.radius
      );
    elsif tg_op='UPDATE' and old.status='active' and new.status='deleted' then
      v_kind := 'VILLAGE_DELETED';
      v_payload := jsonb_build_object('village_id',new.id,'name',new.name);
    end if;

    if v_kind is not null and v_clan_id is not null then
      perform private.prisma_clan_record_activity(v_clan_id,v_user_id,v_kind,0,v_payload);
    end if;

  elsif tg_table_name='clan_wars' then
    if tg_op='INSERT' then
      perform private.prisma_clan_record_activity(
        new.clan_a,null,'WAR_DECLARED',0,
        jsonb_build_object(
          'war_id',new.id,
          'opponent_clan_id',new.clan_b,
          'status',new.status,
          'score_a',new.score_a,
          'score_b',new.score_b
        )
      );
      perform private.prisma_clan_record_activity(
        new.clan_b,null,'WAR_DECLARED',0,
        jsonb_build_object(
          'war_id',new.id,
          'opponent_clan_id',new.clan_a,
          'status',new.status,
          'score_a',new.score_b,
          'score_b',new.score_a
        )
      );
    elsif tg_op='UPDATE' and old.status is distinct from new.status then
      v_kind := case new.status
        when 'active' then 'WAR_ACTIVE'
        when 'finished' then 'WAR_FINISHED'
        when 'cancelled' then 'WAR_CANCELLED'
        else 'WAR_UPDATED'
      end;

      perform private.prisma_clan_record_activity(
        new.clan_a,null,v_kind,0,
        jsonb_build_object(
          'war_id',new.id,
          'opponent_clan_id',new.clan_b,
          'status',new.status,
          'winner_clan_id',new.winner_clan_id,
          'score_for',new.score_a,
          'score_against',new.score_b
        )
      );
      perform private.prisma_clan_record_activity(
        new.clan_b,null,v_kind,0,
        jsonb_build_object(
          'war_id',new.id,
          'opponent_clan_id',new.clan_a,
          'status',new.status,
          'winner_clan_id',new.winner_clan_id,
          'score_for',new.score_b,
          'score_against',new.score_a
        )
      );
    end if;
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

create or replace function private.prisma_clan_activity_achievement_trigger()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform private.prisma_clan_unlock_achievements(new.clan_id);
  return new;
end;
$function$;

drop trigger if exists trg_prisma_clan_members_activity on public.clan_members;
create trigger trg_prisma_clan_members_activity
after insert or update on public.clan_members
for each row execute function private.prisma_clan_entity_activity();

drop trigger if exists trg_prisma_clan_invitations_activity on public.clan_invitations;
create trigger trg_prisma_clan_invitations_activity
after insert or update on public.clan_invitations
for each row execute function private.prisma_clan_entity_activity();

drop trigger if exists trg_prisma_clan_announcements_activity on public.clan_announcements;
create trigger trg_prisma_clan_announcements_activity
after insert or delete on public.clan_announcements
for each row execute function private.prisma_clan_entity_activity();

drop trigger if exists trg_prisma_clan_villages_activity on public.clan_villages;
create trigger trg_prisma_clan_villages_activity
after insert or update on public.clan_villages
for each row execute function private.prisma_clan_entity_activity();

drop trigger if exists trg_prisma_clan_wars_activity on public.clan_wars;
create trigger trg_prisma_clan_wars_activity
after insert or update on public.clan_wars
for each row execute function private.prisma_clan_entity_activity();

drop trigger if exists trg_prisma_clan_activity_achievements on public.clan_activity;
create trigger trg_prisma_clan_activity_achievements
after insert on public.clan_activity
for each row execute function private.prisma_clan_activity_achievement_trigger();

create index if not exists idx_clan_activity_clan_created
on public.clan_activity(clan_id,created_at desc);

create index if not exists idx_clan_achievements_clan_unlocked
on public.clan_achievements(clan_id,unlocked_at desc);

-- Payload-aware participant read endpoint.
create or replace function private.prisma_participant_get_clan_activity(
  p_user_id uuid,
  p_clan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  result jsonb;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',ca.id,
        'kind',ca.kind,
        'xp',ca.xp,
        'payload',ca.payload,
        'created_at',ca.created_at,
        'nickname',u.minecraft_nickname
      )
      order by ca.created_at desc
    ) filter (where ca.id is not null),
    '[]'::jsonb
  )
  into result
  from public.clan_activity ca
  left join public.users u on u.id=ca.user_id
  where ca.clan_id=p_clan_id;

  return result;
end;
$function$;

create or replace function public.participant_get_clan_activity(p_clan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_clan_activity(uid,p_clan_id);
end;
$function$;

revoke all on function public.participant_get_clan_activity(uuid) from public,anon;
grant execute on function public.participant_get_clan_activity(uuid) to authenticated;

-- Keep the clan role RPC independent from the activity trigger to avoid duplicate ROLE_CHANGE rows.
create or replace function public.mc_set_clan_role(
  p_user_id uuid,
  p_target_nickname text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_clan_id uuid;
  v_actor_role text;
  v_target_id uuid;
  v_target_name text;
  v_old_role text;
  v_new_role text:=lower(trim(coalesce(p_role,'')));
  v_actor_level integer;
  v_target_level integer;
  v_new_level integer;
  v_clan_name text;
  v_actor_name text;
begin
  select cm.clan_id,cm.role,c.name into v_clan_id,v_actor_role,v_clan_name
  from public.clan_members cm
  join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active'
    and c.status='active' and c.deleted_at is null
  limit 1;

  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_new_role not in ('co_owner','officer','member','recruit') then raise exception 'INVALID_ROLE'; end if;

  v_actor_level:=case v_actor_role
    when 'owner' then 50
    when 'co_owner' then 40
    when 'officer' then 30
    when 'member' then 20
    when 'recruit' then 10
    else 0 end;

  v_new_level:=case v_new_role
    when 'co_owner' then 40
    when 'officer' then 30
    when 'member' then 20
    when 'recruit' then 10
    else 0 end;

  if v_actor_level < 30 or v_new_level >= v_actor_level then raise exception 'NO_CLAN_PERMISSION'; end if;

  select u.id,u.minecraft_nickname into v_target_id,v_target_name
  from public.users u
  where lower(u.minecraft_nickname)=lower(trim(coalesce(p_target_nickname,'')))
    and u.deleted_at is null
  limit 1;

  if v_target_id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if v_target_id=p_user_id then raise exception 'CANNOT_MANAGE_SELF'; end if;

  select cm.role into v_old_role
  from public.clan_members cm
  where cm.user_id=v_target_id and cm.clan_id=v_clan_id and cm.status='active'
  limit 1;

  if v_old_role is null then raise exception 'TARGET_NOT_IN_CLAN'; end if;

  v_target_level:=case v_old_role
    when 'owner' then 50
    when 'co_owner' then 40
    when 'officer' then 30
    when 'member' then 20
    when 'recruit' then 10
    else 0 end;

  if v_old_role='owner' or v_target_level >= v_actor_level then raise exception 'TARGET_INVALID_ROLE'; end if;
  if v_old_role=v_new_role then raise exception 'ROLE_UNCHANGED'; end if;

  update public.clan_members
  set role=v_new_role
  where clan_id=v_clan_id and user_id=v_target_id and status='active';

  select minecraft_nickname into v_actor_name from public.users where id=p_user_id limit 1;

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  select
    p_user_id,u.telegram_id,'CLAN_ROLE_CHANGE','clan_member',v_target_id,
    jsonb_build_object('clan_id',v_clan_id,'role',v_old_role,'nickname',v_target_name),
    jsonb_build_object('clan_id',v_clan_id,'role',v_new_role,'nickname',v_target_name)
  from public.users u where u.id=p_user_id limit 1;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    target.id,target.telegram_id,'telegram','CLAN',
    'Изменена роль в клане',
    'В клане "'||v_clan_name||'" ваша роль изменена на "'||
      case v_new_role
        when 'co_owner' then 'Совладелец'
        when 'officer' then 'Офицер'
        when 'member' then 'Участник'
        when 'recruit' then 'Рекрут'
      end||'".',
    jsonb_build_object(
      'clan_id',v_clan_id,'old_role',v_old_role,'role',v_new_role,
      'actor_nickname',coalesce(v_actor_name,'Система PRISMA'),'source','participant_site'
    ),
    'pending',now()
  from public.users target
  where target.id=v_target_id
    and target.deleted_at is null
    and target.status='ACCEPTED'::public.application_status
    and not target.is_banned;

  return jsonb_build_object(
    'success',true,'target',v_target_name,'old_role',v_old_role,'role',v_new_role
  );
end;
$function$;

revoke all on function private.prisma_clan_record_activity(uuid,uuid,text,integer,jsonb) from public;
revoke all on function private.prisma_clan_unlock_achievements(uuid) from public;
revoke all on function private.prisma_clan_entity_activity() from public;
revoke all on function private.prisma_clan_activity_achievement_trigger() from public;
revoke all on function private.prisma_participant_get_clan_activity(uuid,uuid) from public;
