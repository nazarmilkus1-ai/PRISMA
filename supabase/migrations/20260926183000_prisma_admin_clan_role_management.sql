create or replace function public.staff_update_clan_member_role(
  p_target_user_id uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_id uuid;
  v_target_clan_id uuid;
  v_target_role text;
  v_target_name text;
  v_new_role text:=lower(trim(coalesce(p_role,'')));
  v_clan_name text;
  v_actor_tg_id bigint;
  v_actor_name text;
begin
  select u.id,u.telegram_id,u.minecraft_nickname
    into v_actor_id,v_actor_tg_id,v_actor_name
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if v_actor_id is null then raise exception 'ADMIN_PROFILE_NOT_LINKED'; end if;

  if not exists (
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=v_actor_id and p.key='clan.manage'
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if p_target_user_id is null then raise exception 'TARGET_REQUIRED'; end if;
  if v_new_role not in ('co_owner','officer','member','recruit') then
    raise exception 'INVALID_ROLE';
  end if;

  select cm.clan_id,cm.role,u.minecraft_nickname,c.name
    into v_target_clan_id,v_target_role,v_target_name,v_clan_name
  from public.clan_members cm
  join public.users u on u.id=cm.user_id
  join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_target_user_id
    and cm.status='active'
    and c.status='active'
    and c.deleted_at is null
    and u.deleted_at is null
  limit 1;

  if v_target_clan_id is null then raise exception 'TARGET_NOT_IN_CLAN'; end if;
  if v_target_role='owner' then raise exception 'OWNER_PROTECTED'; end if;
  if v_target_role=v_new_role then raise exception 'ROLE_UNCHANGED'; end if;

  update public.clan_members
  set role=v_new_role
  where user_id=p_target_user_id
    and clan_id=v_target_clan_id
    and status='active';

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  values(
    v_actor_id,v_actor_tg_id,'ADMIN_CLAN_ROLE_CHANGE','clan_member',p_target_user_id,
    jsonb_build_object(
      'clan_id',v_target_clan_id,'clan_name',v_clan_name,
      'role',v_target_role,'nickname',v_target_name
    ),
    jsonb_build_object(
      'clan_id',v_target_clan_id,'clan_name',v_clan_name,
      'role',v_new_role,'nickname',v_target_name
    )
  );

  insert into public.clan_activity(clan_id,user_id,kind,xp,created_at)
  values(v_target_clan_id,p_target_user_id,'ADMIN_ROLE_CHANGE',0,now());

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    u.id,u.telegram_id,'telegram','CLAN',
    'Администратор изменил роль',
    'В клане "'||v_clan_name||'" ваша роль изменена на "'||
      case v_new_role
        when 'co_owner' then 'Совладелец'
        when 'officer' then 'Офицер'
        when 'member' then 'Участник'
        when 'recruit' then 'Рекрут'
      end||'".',
    jsonb_build_object(
      'clan_id',v_target_clan_id,
      'old_role',v_target_role,
      'role',v_new_role,
      'actor_user_id',v_actor_id,
      'actor_nickname',coalesce(v_actor_name,'Администратор'),
      'source','admin_panel'
    ),
    'pending',now()
  from public.users u
  where u.id=p_target_user_id
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned;

  return jsonb_build_object(
    'success',true,
    'clan_id',v_target_clan_id,
    'target_user_id',p_target_user_id,
    'nickname',v_target_name,
    'old_role',v_target_role,
    'role',v_new_role
  );
end;
$function$;

revoke execute on function public.staff_update_clan_member_role(uuid,text) from public,anon,authenticated;
grant execute on function public.staff_update_clan_member_role(uuid,text) to authenticated;