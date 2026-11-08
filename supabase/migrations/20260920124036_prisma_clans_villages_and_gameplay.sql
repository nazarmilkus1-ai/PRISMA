create table if not exists public.clan_villages (
  id uuid primary key default gen_random_uuid(),
  clan_id uuid not null references public.clans(id) on delete cascade,
  name text not null,
  world text not null,
  center_x double precision not null,
  center_y double precision not null,
  center_z double precision not null,
  radius integer not null default 48,
  status text not null default 'active',
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clan_villages_radius_check check (radius between 24 and 96),
  constraint clan_villages_status_check check (status in ('active','deleted'))
);

create unique index if not exists clan_villages_name_lower_idx
  on public.clan_villages(clan_id, lower(name)) where status='active';
create index if not exists clan_villages_world_idx
  on public.clan_villages(world,status);
create index if not exists clan_villages_clan_idx
  on public.clan_villages(clan_id,status);
alter table public.clan_villages enable row level security;

create or replace function public.mc_check_staff_permission(p_user_id uuid,p_permission_key text)
returns boolean language sql stable security definer set search_path=''
as $$
select exists(
  select 1 from public.admins a
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where a.user_id=p_user_id and p.key=p_permission_key
);
$$;

create or replace function public.mc_get_clan_context(p_user_id uuid)
returns json language sql stable security definer set search_path=''
as $$
select coalesce((
  select json_build_object(
    'clan_id',c.id,'name',c.name,'tag',c.tag,'owner_id',c.owner_id,
    'rating',c.rating,'level',c.level,'xp',c.xp,'balance',c.balance,
    'wins',c.wins,'losses',c.losses,'member_role',cm.role
  )
  from public.clan_members cm join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active'
    and c.deleted_at is null and c.status='active'
  limit 1
),'{}'::json);
$$;

create or replace function public.mc_list_clan_villages(p_user_id uuid)
returns json language sql stable security definer set search_path=''
as $$
select coalesce(json_build_object('villages',json_agg(row_to_json(v) order by v.created_at)),'{"villages":[]}'::json)
from (
  select cv.id,cv.clan_id,cv.name,cv.world,cv.center_x,cv.center_y,cv.center_z,
         cv.radius,cv.created_by,cv.created_at
  from public.clan_villages cv
  where cv.status='active'
    and cv.clan_id=(select cm.clan_id from public.clan_members cm
                    where cm.user_id=p_user_id and cm.status='active' limit 1)
) v;
$$;

create or replace function public.mc_get_village_at(p_world text,p_x double precision,p_z double precision)
returns json language sql stable security definer set search_path=''
as $$
select coalesce((
  select json_build_object(
    'id',cv.id,'clan_id',cv.clan_id,'name',cv.name,'world',cv.world,
    'center_x',cv.center_x,'center_y',cv.center_y,'center_z',cv.center_z,
    'radius',cv.radius,'clan_name',c.name,'clan_tag',c.tag
  )
  from public.clan_villages cv join public.clans c on c.id=cv.clan_id
  where cv.status='active' and c.status='active' and c.deleted_at is null
    and cv.world=p_world
    and ((cv.center_x-p_x)*(cv.center_x-p_x)+(cv.center_z-p_z)*(cv.center_z-p_z))
        <= cv.radius*cv.radius
  order by cv.radius asc
  limit 1
),'{}'::json);
$$;

create or replace function public.mc_create_village(
  p_user_id uuid,p_name text,p_world text,p_x double precision,p_y double precision,
  p_z double precision,p_radius integer default 48
) returns json language plpgsql security definer set search_path=''
as $$
declare
  v_clan_id uuid; v_role text; v_id uuid; v_name text;
  v_radius integer:=greatest(24,least(96,coalesce(p_radius,48))); v_count integer;
begin
  select cm.clan_id,cm.role into v_clan_id,v_role
  from public.clan_members cm join public.clans c on c.id=cm.clan_id
  where cm.user_id=p_user_id and cm.status='active'
    and c.status='active' and c.deleted_at is null limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role not in ('owner','officer') then raise exception 'NO_VILLAGE_PERMISSION'; end if;

  v_name:=trim(p_name);
  if v_name is null or char_length(v_name) not between 2 and 32 then raise exception 'INVALID_VILLAGE_NAME'; end if;
  select count(*) into v_count from public.clan_villages where clan_id=v_clan_id and status='active';
  if v_count>=3 then raise exception 'VILLAGE_LIMIT_REACHED'; end if;
  if p_world is null or trim(p_world)='' then raise exception 'INVALID_WORLD'; end if;

  if exists(
    select 1 from public.clan_villages cv
    where cv.status='active' and cv.world=p_world
      and ((cv.center_x-p_x)*(cv.center_x-p_x)+(cv.center_z-p_z)*(cv.center_z-p_z))
          <= (cv.radius+v_radius)*(cv.radius+v_radius)
  ) then raise exception 'VILLAGE_OVERLAP'; end if;

  insert into public.clan_villages(clan_id,name,world,center_x,center_y,center_z,radius,created_by)
  values(v_clan_id,v_name,p_world,p_x,p_y,p_z,v_radius,p_user_id) returning id into v_id;
  update public.clans set updated_at=now() where id=v_clan_id;
  return json_build_object('success',true,'id',v_id,'clan_id',v_clan_id,'name',v_name,
                           'world',p_world,'x',p_x,'y',p_y,'z',p_z,'radius',v_radius);
end;
$$;

create or replace function public.mc_delete_village(p_user_id uuid,p_village_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
declare v_clan_id uuid; v_role text;
begin
  select clan_id,role into v_clan_id,v_role from public.clan_members
  where user_id=p_user_id and status='active' limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
  update public.clan_villages set status='deleted',updated_at=now()
  where id=p_village_id and clan_id=v_clan_id and status='active';
  if not found then raise exception 'VILLAGE_NOT_FOUND'; end if;
  return json_build_object('success',true,'village_id',p_village_id);
end;
$$;

create or replace function public.mc_set_village_radius(p_user_id uuid,p_village_id uuid,p_radius integer)
returns json language plpgsql security definer set search_path=''
as $$
declare v_clan_id uuid; v_role text; v_radius integer:=greatest(24,least(96,coalesce(p_radius,48)));
begin
  select clan_id,role into v_clan_id,v_role from public.clan_members
  where user_id=p_user_id and status='active' limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
  if exists(
    select 1 from public.clan_villages a
    where a.id=p_village_id and a.clan_id=v_clan_id and a.status='active'
      and exists(
        select 1 from public.clan_villages b
        where b.id<>a.id and b.status='active' and b.world=a.world
          and ((a.center_x-b.center_x)*(a.center_x-b.center_x)+(a.center_z-b.center_z)*(a.center_z-b.center_z))
              <= (v_radius+b.radius)*(v_radius+b.radius)
      )
  ) then raise exception 'VILLAGE_OVERLAP'; end if;
  update public.clan_villages set radius=v_radius,updated_at=now()
  where id=p_village_id and clan_id=v_clan_id and status='active';
  if not found then raise exception 'VILLAGE_NOT_FOUND'; end if;
  return json_build_object('success',true,'radius',v_radius);
end;
$$;

create or replace function public.mc_invite_player(p_user_id uuid,p_target_nickname text)
returns json language plpgsql security definer set search_path=''
as $$
declare v_clan_id uuid; v_role text; v_target_id uuid; v_invite_id uuid;
begin
  select clan_id,role into v_clan_id,v_role from public.clan_members
  where user_id=p_user_id and status='active' limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;
  if v_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
  select id into v_target_id from public.users
  where lower(minecraft_nickname)=lower(trim(p_target_nickname)) limit 1;
  if v_target_id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  if exists(select 1 from public.clan_members where user_id=v_target_id and status='active')
    then raise exception 'PLAYER_ALREADY_IN_CLAN'; end if;
  if exists(select 1 from public.clan_invitations
            where clan_id=v_clan_id and invitee_id=v_target_id and status='pending' and expires_at>now())
    then raise exception 'INVITE_ALREADY_EXISTS'; end if;
  insert into public.clan_invitations(clan_id,inviter_id,invitee_id,status)
  values(v_clan_id,p_user_id,v_target_id,'pending') returning id into v_invite_id;
  return json_build_object('success',true,'invite_id',v_invite_id,'target_user_id',v_target_id);
end;
$$;

create or replace function public.mc_list_clan_invites(p_user_id uuid)
returns json language sql stable security definer set search_path=''
as $$
select json_build_object('invites',coalesce(json_agg(row_to_json(i) order by i.created_at desc),'[]'::json))
from (
  select ci.id,ci.clan_id,c.name,c.tag,ci.inviter_id,u.minecraft_nickname as inviter_nickname,
         ci.expires_at,ci.created_at
  from public.clan_invitations ci join public.clans c on c.id=ci.clan_id
  left join public.users u on u.id=ci.inviter_id
  where ci.invitee_id=p_user_id and ci.status='pending' and ci.expires_at>now()
) i;
$$;

create or replace function public.mc_accept_clan_invite(p_user_id uuid,p_invite_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
declare v_clan_id uuid; v_clan_name text; v_clan_tag text; v_current uuid;
begin
  if exists(select 1 from public.clan_members where user_id=p_user_id and status='active')
    then raise exception 'USER_ALREADY_IN_CLAN'; end if;
  select ci.clan_id,c.name,c.tag into v_clan_id,v_clan_name,v_clan_tag
  from public.clan_invitations ci join public.clans c on c.id=ci.clan_id
  where ci.id=p_invite_id and ci.invitee_id=p_user_id and ci.status='pending' and ci.expires_at>now()
  limit 1;
  if v_clan_id is null then raise exception 'INVITE_NOT_FOUND'; end if;
  update public.clan_invitations set status='accepted',responded_at=now() where id=p_invite_id;
  select user_id into v_current from public.clan_members where user_id=p_user_id limit 1;
  if v_current is null then
    insert into public.clan_members(clan_id,user_id,role,status) values(v_clan_id,p_user_id,'member','active');
  else
    update public.clan_members set clan_id=v_clan_id,role='member',status='active',joined_at=now()
    where user_id=p_user_id;
  end if;
  update public.users set clan_id=v_clan_id,updated_at=now() where id=p_user_id;
  update public.clan_invitations set status='expired',responded_at=coalesce(responded_at,now())
  where invitee_id=p_user_id and status='pending' and id<>p_invite_id;
  return json_build_object('success',true,'clan_id',v_clan_id,'name',v_clan_name,'tag',v_clan_tag);
end;
$$;

create or replace function public.mc_decline_clan_invite(p_user_id uuid,p_invite_id uuid)
returns json language plpgsql security definer set search_path=''
as $$
begin
  update public.clan_invitations set status='declined',responded_at=now()
  where id=p_invite_id and invitee_id=p_user_id and status='pending';
  if not found then raise exception 'INVITE_NOT_FOUND'; end if;
  return json_build_object('success',true);
end;
$$;

create or replace function public.mc_clan_action(p_user_id uuid,p_action text,p_target_nickname text default null)
returns json language plpgsql security definer set search_path=''
as $$
declare v_clan_id uuid; v_actor_role text; v_target_id uuid; v_target_role text; v_target_name text;
begin
  select clan_id,role into v_clan_id,v_actor_role from public.clan_members
  where user_id=p_user_id and status='active' limit 1;
  if v_clan_id is null then raise exception 'NO_CLAN'; end if;

  if p_action='DISBAND' then
    if v_actor_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
    update public.users set clan_id=null,updated_at=now() where clan_id=v_clan_id;
    update public.clan_members set status='left' where clan_id=v_clan_id and status='active';
    update public.clan_villages set status='deleted',updated_at=now() where clan_id=v_clan_id and status='active';
    update public.clans set status='deleted',deleted_at=now(),updated_at=now() where id=v_clan_id;
    return json_build_object('success',true,'action','DISBAND');
  end if;

  if p_target_nickname is null or trim(p_target_nickname)='' then raise exception 'TARGET_REQUIRED'; end if;
  select id,minecraft_nickname into v_target_id,v_target_name from public.users
  where lower(minecraft_nickname)=lower(trim(p_target_nickname)) limit 1;
  if v_target_id is null then raise exception 'PLAYER_NOT_FOUND'; end if;
  select role into v_target_role from public.clan_members
  where user_id=v_target_id and clan_id=v_clan_id and status='active' limit 1;

  if p_action='KICK' then
    if v_actor_role not in ('owner','officer') then raise exception 'NO_CLAN_PERMISSION'; end if;
    if v_target_role is null or v_target_id=p_user_id or v_target_role='owner' then raise exception 'CANNOT_KICK'; end if;
    if v_actor_role='officer' and v_target_role='officer' then raise exception 'CANNOT_KICK'; end if;
    update public.clan_members set status='left' where user_id=v_target_id and clan_id=v_clan_id;
    update public.users set clan_id=null,updated_at=now() where id=v_target_id;
  elsif p_action='PROMOTE' then
    if v_actor_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
    if v_target_role<>'member' then raise exception 'TARGET_INVALID_ROLE'; end if;
    update public.clan_members set role='officer' where user_id=v_target_id and clan_id=v_clan_id;
  elsif p_action='DEMOTE' then
    if v_actor_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
    if v_target_role<>'officer' then raise exception 'TARGET_INVALID_ROLE'; end if;
    update public.clan_members set role='member' where user_id=v_target_id and clan_id=v_clan_id;
  elsif p_action='TRANSFER' then
    if v_actor_role<>'owner' then raise exception 'OWNER_ONLY'; end if;
    if v_target_role is null or v_target_id=p_user_id then raise exception 'TARGET_NOT_IN_CLAN'; end if;
    update public.clans set owner_id=v_target_id,updated_at=now() where id=v_clan_id;
    update public.clan_members set role='member' where clan_id=v_clan_id and user_id=p_user_id;
    update public.clan_members set role='owner' where clan_id=v_clan_id and user_id=v_target_id;
  else
    raise exception 'UNKNOWN_ACTION';
  end if;

  return json_build_object('success',true,'action',p_action,'target',v_target_name);
end;
$$;

revoke execute on function public.mc_check_staff_permission(uuid,text) from public;
revoke execute on function public.mc_get_clan_context(uuid) from public;
revoke execute on function public.mc_list_clan_villages(uuid) from public;
revoke execute on function public.mc_get_village_at(text,double precision,double precision) from public;
revoke execute on function public.mc_create_village(uuid,text,text,double precision,double precision,double precision,integer) from public;
revoke execute on function public.mc_delete_village(uuid,uuid) from public;
revoke execute on function public.mc_set_village_radius(uuid,uuid,integer) from public;
revoke execute on function public.mc_invite_player(uuid,text) from public;
revoke execute on function public.mc_list_clan_invites(uuid) from public;
revoke execute on function public.mc_accept_clan_invite(uuid,uuid) from public;
revoke execute on function public.mc_decline_clan_invite(uuid,uuid) from public;
revoke execute on function public.mc_clan_action(uuid,text,text) from public;

grant execute on function public.mc_check_staff_permission(uuid,text) to service_role;
grant execute on function public.mc_get_clan_context(uuid) to service_role;
grant execute on function public.mc_list_clan_villages(uuid) to service_role;
grant execute on function public.mc_get_village_at(text,double precision,double precision) to service_role;
grant execute on function public.mc_create_village(uuid,text,text,double precision,double precision,double precision,integer) to service_role;
grant execute on function public.mc_delete_village(uuid,uuid) to service_role;
grant execute on function public.mc_set_village_radius(uuid,uuid,integer) to service_role;
grant execute on function public.mc_invite_player(uuid,text) to service_role;
grant execute on function public.mc_list_clan_invites(uuid) to service_role;
grant execute on function public.mc_accept_clan_invite(uuid,uuid) to service_role;
grant execute on function public.mc_decline_clan_invite(uuid,uuid) to service_role;
grant execute on function public.mc_clan_action(uuid,text,text) to service_role;
