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
  select cm.clan_id,cm.role,c.name
    into v_clan_id,v_actor_role,v_clan_name
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

  if v_actor_level < 30 or v_new_level >= v_actor_level then
    raise exception 'NO_CLAN_PERMISSION';
  end if;

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

  if v_old_role='owner' or v_target_level >= v_actor_level then
    raise exception 'TARGET_INVALID_ROLE';
  end if;
  if v_old_role=v_new_role then raise exception 'ROLE_UNCHANGED'; end if;

  update public.clan_members
  set role=v_new_role
  where clan_id=v_clan_id and user_id=v_target_id and status='active';

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  select
    p_user_id,u.telegram_id,'CLAN_ROLE_CHANGE','clan_member',v_target_id,
    jsonb_build_object('clan_id',v_clan_id,'role',v_old_role,'nickname',v_target_name),
    jsonb_build_object('clan_id',v_clan_id,'role',v_new_role,'nickname',v_target_name)
  from public.users u
  where u.id=p_user_id
  limit 1;

  select minecraft_nickname into v_actor_name
  from public.users
  where id=p_user_id
  limit 1;

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
      'clan_id',v_clan_id,
      'old_role',v_old_role,
      'role',v_new_role,
      'actor_nickname',coalesce(v_actor_name,'Система PRISMA'),
      'source','participant_site'
    ),
    'pending',now()
  from public.users target
  where target.id=v_target_id
    and target.deleted_at is null
    and target.status='ACCEPTED'::public.application_status
    and not target.is_banned;

  return jsonb_build_object(
    'success',true,
    'target',v_target_name,
    'old_role',v_old_role,
    'role',v_new_role
  );
end;
$function$;

create or replace function public.participant_set_clan_role(
  p_target_nickname text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return public.mc_set_clan_role(uid,p_target_nickname,p_role);
end;
$function$;

revoke all on function public.mc_set_clan_role(uuid,text,text) from public,anon,authenticated;
grant execute on function public.mc_set_clan_role(uuid,text,text) to service_role;

revoke all on function public.participant_set_clan_role(text,text) from public,anon;
grant execute on function public.participant_set_clan_role(text,text) to authenticated;
