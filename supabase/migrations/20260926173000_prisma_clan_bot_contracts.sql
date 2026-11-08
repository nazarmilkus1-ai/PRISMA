create or replace function public.mc_invite_player(p_user_id uuid,p_target_nickname text)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_clan_id uuid;
  v_role text;
  v_target_id uuid;
  v_invite_id uuid;
  v_clan_name text;
  v_clan_tag text;
  v_inviter_name text;
begin
  select cm.clan_id,cm.role,c.name,c.tag
    into v_clan_id,v_role,v_clan_name,v_clan_tag
  from public.clan_members cm
  join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active'
    and c.status='active' and c.deleted_at is null
  limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;

  select u.id into v_target_id from public.users u
  where lower(u.minecraft_nickname)=lower(trim(p_target_nickname))
    and u.deleted_at is null limit 1;
  if v_target_id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if v_target_id=p_user_id then raise exception 'CANNOT_INVITE_SELF'; end if;
  if exists(select 1 from public.clan_members cm where cm.user_id=v_target_id and cm.status='active')
    then raise exception 'PLAYER_ALREADY_IN_CLAN'; end if;
  if exists(
    select 1 from public.clan_invitations ci
    where ci.clan_id=v_clan_id and ci.invitee_id=v_target_id
      and ci.status='pending' and ci.expires_at > now()
  ) then raise exception 'INVITE_ALREADY_EXISTS'; end if;

  insert into public.clan_invitations(clan_id,inviter_id,invitee_id,status)
  values(v_clan_id,p_user_id,v_target_id,'pending')
  returning id into v_invite_id;

  select minecraft_nickname into v_inviter_name
  from public.users where id=p_user_id limit 1;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    target.id,target.telegram_id,'telegram','CLAN',
    'Приглашение в клан',
    'Игрок "'||coalesce(v_inviter_name,'Участник PRISMA')||
      '" приглашает вас в клан ['||coalesce(v_clan_tag,'—')||'] '||coalesce(v_clan_name,'Клан')||'.',
    jsonb_build_object(
      'clan_id',v_clan_id,'invite_id',v_invite_id,
      'inviter_user_id',p_user_id,'source','clan_invite'
    ),
    'pending',now()
  from public.users target
  where target.id=v_target_id
    and target.deleted_at is null
    and target.status='ACCEPTED'::public.application_status
    and not target.is_banned;

  return json_build_object(
    'success',true,'invite_id',v_invite_id,
    'target_user_id',v_target_id,'clan_id',v_clan_id
  );
end;
$function$;

create or replace function public.bot_clan_invite(p_tg_id bigint,p_target_nickname text)
returns json
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_invite_player(uid,p_target_nickname);
end;
$function$;

create or replace function public.bot_set_clan_role(p_tg_id bigint,p_target_nickname text,p_role text)
returns jsonb
language plpgsql security definer set search_path='public'
as $function$
declare uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return public.mc_set_clan_role(uid,p_target_nickname,p_role);
end;
$function$;

revoke execute on function public.mc_invite_player(uuid,text) from public,anon,authenticated;
grant execute on function public.mc_invite_player(uuid,text) to service_role;
revoke execute on function public.bot_clan_invite(bigint,text) from public,anon,authenticated;
grant execute on function public.bot_clan_invite(bigint,text) to service_role;
revoke execute on function public.bot_set_clan_role(bigint,text,text) from public,anon,authenticated;
grant execute on function public.bot_set_clan_role(bigint,text,text) to service_role;
