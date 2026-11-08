create or replace function public.mc_clan_action(
  p_user_id uuid,
  p_action text,
  p_target_nickname text default null
)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_clan_id uuid;
  v_actor_role text;
  v_target_id uuid;
  v_target_role text;
  v_target_name text;
  v_actor_tg_id bigint;
  v_actor_name text;
  v_clan_name text;
  v_old_role text;
begin
  select cm.clan_id, cm.role
    into v_clan_id, v_actor_role
  from public.clan_members cm
  where cm.user_id = p_user_id
    and cm.status = 'active'
  limit 1;

  if v_clan_id is null then
    raise exception 'NO_CLAN';
  end if;

  select u.telegram_id, u.minecraft_nickname
    into v_actor_tg_id, v_actor_name
  from public.users u
  where u.id = p_user_id
  limit 1;

  select c.name
    into v_clan_name
  from public.clans c
  where c.id = v_clan_id
  limit 1;

  if p_action = 'DISBAND' then
    if v_actor_role <> 'owner' then
      raise exception 'OWNER_ONLY';
    end if;

    insert into public.notifications(
      user_id,
      telegram_id,
      channel,
      kind,
      title,
      body,
      data,
      status,
      available_at
    )
    select
      u.id,
      u.telegram_id,
      'telegram',
      'CLAN',
      'Клан распущен',
      'Клан «' || coalesce(v_clan_name, 'Клан') || '» был распущен владельцем.',
      jsonb_build_object(
        'clan_id', v_clan_id,
        'action', 'DISBAND',
        'source', 'clan_action'
      ),
      'pending',
      now()
    from public.clan_members cm
    join public.users u on u.id = cm.user_id
    where cm.clan_id = v_clan_id
      and cm.status = 'active'
      and u.deleted_at is null;

    insert into public.clan_activity(clan_id, user_id, kind, xp, payload, created_at)
    values (
      v_clan_id,
      p_user_id,
      'CLAN_DISBANDED',
      0,
      jsonb_build_object(
        'clan_id', v_clan_id,
        'clan_name', v_clan_name,
        'actor_nickname', v_actor_name
      ),
      now()
    );

    insert into public.audit_logs(
      actor_user_id,
      actor_tg_id,
      action,
      target_type,
      target_id,
      old_data,
      new_data
    )
    values (
      p_user_id,
      v_actor_tg_id,
      'CLAN_DISBAND',
      'clan',
      v_clan_id,
      jsonb_build_object('status', 'active', 'name', v_clan_name),
      jsonb_build_object('status', 'deleted')
    );

    update public.users
    set clan_id = null,
        updated_at = now()
    where clan_id = v_clan_id;

    update public.clan_members
    set status = 'left'
    where clan_id = v_clan_id
      and status = 'active';

    update public.clan_villages
    set status = 'deleted',
        updated_at = now()
    where clan_id = v_clan_id
      and status = 'active';

    update public.clans
    set status = 'deleted',
        deleted_at = now(),
        updated_at = now()
    where id = v_clan_id;

    return json_build_object(
      'success', true,
      'action', 'DISBAND'
    );
  end if;

  if p_target_nickname is null or trim(p_target_nickname) = '' then
    raise exception 'TARGET_REQUIRED';
  end if;

  select u.id, u.minecraft_nickname
    into v_target_id, v_target_name
  from public.users u
  where lower(u.minecraft_nickname) = lower(trim(p_target_nickname))
    and u.deleted_at is null
  limit 1;

  if v_target_id is null then
    raise exception 'PLAYER_NOT_FOUND';
  end if;

  select cm.role
    into v_target_role
  from public.clan_members cm
  where cm.user_id = v_target_id
    and cm.clan_id = v_clan_id
    and cm.status = 'active'
  limit 1;

  if p_action = 'KICK' then
    if v_actor_role not in ('owner', 'officer') then
      raise exception 'NO_CLAN_PERMISSION';
    end if;

    if v_target_role is null then
      raise exception 'TARGET_NOT_IN_CLAN';
    end if;

    if v_target_id = p_user_id or v_target_role = 'owner' then
      raise exception 'CANNOT_KICK';
    end if;

    if v_actor_role = 'officer' and v_target_role = 'officer' then
      raise exception 'CANNOT_KICK';
    end if;

    v_old_role := v_target_role;

    update public.clan_members
    set status = 'left'
    where user_id = v_target_id
      and clan_id = v_clan_id;

    update public.users
    set clan_id = null,
        updated_at = now()
    where id = v_target_id;

    insert into public.clan_activity(clan_id, user_id, kind, xp, payload, created_at)
    values (
      v_clan_id,
      v_target_id,
      'MEMBER_LEAVE',
      0,
      jsonb_build_object(
        'action', 'KICK',
        'nickname', v_target_name,
        'old_role', v_old_role,
        'actor_nickname', v_actor_name
      ),
      now()
    );

    insert into public.audit_logs(
      actor_user_id,
      actor_tg_id,
      action,
      target_type,
      target_id,
      old_data,
      new_data
    )
    values (
      p_user_id,
      v_actor_tg_id,
      'CLAN_MEMBER_KICK',
      'clan_member',
      v_target_id,
      jsonb_build_object(
        'clan_id', v_clan_id,
        'role', v_old_role,
        'nickname', v_target_name,
        'status', 'active'
      ),
      jsonb_build_object(
        'clan_id', v_clan_id,
        'role', v_old_role,
        'nickname', v_target_name,
        'status', 'left'
      )
    );

    insert into public.notifications(
      user_id,
      telegram_id,
      channel,
      kind,
      title,
      body,
      data,
      status,
      available_at
    )
    select
      u.id,
      u.telegram_id,
      'telegram',
      'CLAN',
      'Вы исключены из клана',
      'Вы были исключены из клана «' || coalesce(v_clan_name, 'Клан') || '».',
      jsonb_build_object(
        'clan_id', v_clan_id,
        'action', 'KICK',
        'actor_nickname', v_actor_name,
        'source', 'clan_action'
      ),
      'pending',
      now()
    from public.users u
    where u.id = v_target_id
      and u.deleted_at is null;

  elsif p_action = 'PROMOTE' then
    if v_actor_role <> 'owner' then
      raise exception 'OWNER_ONLY';
    end if;

    if v_target_role <> 'member' then
      raise exception 'TARGET_INVALID_ROLE';
    end if;

    v_old_role := v_target_role;

    update public.clan_members
    set role = 'officer'
    where user_id = v_target_id
      and clan_id = v_clan_id;

    insert into public.clan_activity(clan_id, user_id, kind, xp, payload, created_at)
    values (
      v_clan_id,
      v_target_id,
      'ROLE_CHANGE',
      0,
      jsonb_build_object(
        'old_role', v_old_role,
        'role', 'officer',
        'nickname', v_target_name,
        'actor_nickname', v_actor_name
      ),
      now()
    );

    insert into public.audit_logs(
      actor_user_id,
      actor_tg_id,
      action,
      target_type,
      target_id,
      old_data,
      new_data
    )
    values (
      p_user_id,
      v_actor_tg_id,
      'CLAN_ROLE_CHANGE',
      'clan_member',
      v_target_id,
      jsonb_build_object('clan_id', v_clan_id, 'role', v_old_role, 'nickname', v_target_name),
      jsonb_build_object('clan_id', v_clan_id, 'role', 'officer', 'nickname', v_target_name)
    );

    insert into public.notifications(
      user_id,
      telegram_id,
      channel,
      kind,
      title,
      body,
      data,
      status,
      available_at
    )
    select
      u.id,
      u.telegram_id,
      'telegram',
      'CLAN',
      'Изменена роль в клане',
      'В клане «' || coalesce(v_clan_name, 'Клан') || '» ваша роль изменена на «Офицер».',
      jsonb_build_object(
        'clan_id', v_clan_id,
        'old_role', v_old_role,
        'role', 'officer',
        'actor_nickname', v_actor_name,
        'source', 'clan_action'
      ),
      'pending',
      now()
    from public.users u
    where u.id = v_target_id
      and u.deleted_at is null;

  elsif p_action = 'DEMOTE' then
    if v_actor_role <> 'owner' then
      raise exception 'OWNER_ONLY';
    end if;

    if v_target_role <> 'officer' then
      raise exception 'TARGET_INVALID_ROLE';
    end if;

    v_old_role := v_target_role;

    update public.clan_members
    set role = 'member'
    where user_id = v_target_id
      and clan_id = v_clan_id;

    insert into public.clan_activity(clan_id, user_id, kind, xp, payload, created_at)
    values (
      v_clan_id,
      v_target_id,
      'ROLE_CHANGE',
      0,
      jsonb_build_object(
        'old_role', v_old_role,
        'role', 'member',
        'nickname', v_target_name,
        'actor_nickname', v_actor_name
      ),
      now()
    );

    insert into public.audit_logs(
      actor_user_id,
      actor_tg_id,
      action,
      target_type,
      target_id,
      old_data,
      new_data
    )
    values (
      p_user_id,
      v_actor_tg_id,
      'CLAN_ROLE_CHANGE',
      'clan_member',
      v_target_id,
      jsonb_build_object('clan_id', v_clan_id, 'role', v_old_role, 'nickname', v_target_name),
      jsonb_build_object('clan_id', v_clan_id, 'role', 'member', 'nickname', v_target_name)
    );

    insert into public.notifications(
      user_id,
      telegram_id,
      channel,
      kind,
      title,
      body,
      data,
      status,
      available_at
    )
    select
      u.id,
      u.telegram_id,
      'telegram',
      'CLAN',
      'Изменена роль в клане',
      'В клане «' || coalesce(v_clan_name, 'Клан') || '» ваша роль изменена на «Участник».',
      jsonb_build_object(
        'clan_id', v_clan_id,
        'old_role', v_old_role,
        'role', 'member',
        'actor_nickname', v_actor_name,
        'source', 'clan_action'
      ),
      'pending',
      now()
    from public.users u
    where u.id = v_target_id
      and u.deleted_at is null;

  elsif p_action = 'TRANSFER' then
    if v_actor_role <> 'owner' then
      raise exception 'OWNER_ONLY';
    end if;

    if v_target_role is null or v_target_id = p_user_id then
      raise exception 'TARGET_NOT_IN_CLAN';
    end if;

    if v_target_role = 'owner' then
      raise exception 'TARGET_INVALID_ROLE';
    end if;

    update public.clans
    set owner_id = v_target_id,
        updated_at = now()
    where id = v_clan_id;

    update public.clan_members
    set role = 'member'
    where clan_id = v_clan_id
      and user_id = p_user_id;

    update public.clan_members
    set role = 'owner'
    where clan_id = v_clan_id
      and user_id = v_target_id;

    insert into public.clan_activity(clan_id, user_id, kind, xp, payload, created_at)
    values (
      v_clan_id,
      v_target_id,
      'OWNER_TRANSFER',
      0,
      jsonb_build_object(
        'old_owner_nickname', v_actor_name,
        'new_owner_nickname', v_target_name
      ),
      now()
    );

    insert into public.audit_logs(
      actor_user_id,
      actor_tg_id,
      action,
      target_type,
      target_id,
      old_data,
      new_data
    )
    values (
      p_user_id,
      v_actor_tg_id,
      'CLAN_OWNER_TRANSFER',
      'clan',
      v_clan_id,
      jsonb_build_object(
        'owner_id', p_user_id,
        'owner_nickname', v_actor_name
      ),
      jsonb_build_object(
        'owner_id', v_target_id,
        'owner_nickname', v_target_name
      )
    );

    insert into public.notifications(
      user_id,
      telegram_id,
      channel,
      kind,
      title,
      body,
      data,
      status,
      available_at
    )
    select
      u.id,
      u.telegram_id,
      'telegram',
      'CLAN',
      case when u.id = v_target_id then 'Вы стали владельцем клана' else 'Передан владелец клана' end,
      case
        when u.id = v_target_id
          then 'Теперь вы владелец клана «' || coalesce(v_clan_name, 'Клан') || '».'
        else 'В клане «' || coalesce(v_clan_name, 'Клан') || '» владелец передан игроку «' || coalesce(v_target_name, 'игрок') || '».'
      end,
      jsonb_build_object(
        'clan_id', v_clan_id,
        'action', 'TRANSFER',
        'previous_owner_id', p_user_id,
        'new_owner_id', v_target_id,
        'source', 'clan_action'
      ),
      'pending',
      now()
    from public.users u
    where u.id in (p_user_id, v_target_id)
      and u.deleted_at is null;

  else
    raise exception 'UNKNOWN_ACTION';
  end if;

  return json_build_object(
    'success', true,
    'action', p_action,
    'target', v_target_name
  );
end;
$function$;

grant execute on function public.mc_clan_action(uuid, text, text) to authenticated;
revoke execute on function public.mc_clan_action(uuid, text, text) from anon;
