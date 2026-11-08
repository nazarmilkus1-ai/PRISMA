-- Atomic clan-war gateways. Browser clients never submit actor user IDs.

create or replace function private.prisma_participant_create_clan_war(
  p_user_id uuid,p_target text
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; target_clan_id uuid; war_id uuid; lock_key bigint;
begin
  if p_user_id is null then raise exception 'USER_NOT_LINKED'; end if;
  if p_target is null or char_length(trim(p_target))<1 or char_length(trim(p_target))>64
    then raise exception 'CLAN_NOT_FOUND'; end if;

  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active'
  order by case cm.role when 'owner' then 0 when 'officer' then 1 else 2 end
  limit 1 for update;

  if actor_clan_id is null or actor_role not in ('owner','officer') then
    raise exception 'NO_CLAN_PERMISSION';
  end if;

  select c.id into target_clan_id
  from public.clans c
  where c.deleted_at is null and c.status='active' and c.id<>actor_clan_id
    and (lower(trim(c.tag))=lower(trim(p_target)) or lower(trim(c.name))=lower(trim(p_target)))
  order by case when lower(trim(c.tag))=lower(trim(p_target)) then 0 else 1 end
  limit 1;

  if target_clan_id is null then raise exception 'CLAN_NOT_FOUND'; end if;

  lock_key:=hashtextextended(
    least(actor_clan_id::text,target_clan_id::text)||':'||
    greatest(actor_clan_id::text,target_clan_id::text),2147483647
  );
  perform pg_advisory_xact_lock(lock_key);

  if exists(
    select 1 from public.clan_wars w
    where w.status in ('scheduled','active')
      and (w.clan_a=actor_clan_id or w.clan_b=actor_clan_id)
  ) then
    raise exception 'WAR_ALREADY_ACTIVE';
  end if;

  insert into public.clan_wars(clan_a,clan_b,status,scheduled_at,score_a,score_b)
  values(actor_clan_id,target_clan_id,'scheduled',now(),0,0)
  returning id into war_id;

  return jsonb_build_object('success',true,'war_id',war_id,'clan_a',actor_clan_id,'clan_b',target_clan_id);
end;
$function$;

create or replace function public.participant_create_clan_war(p_target text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_create_clan_war(uid,p_target);
end;
$function$;

create or replace function private.prisma_participant_cancel_clan_war(p_user_id uuid,p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor_clan_id uuid; actor_role text; war record;
begin
  select cm.clan_id,cm.role into actor_clan_id,actor_role
  from public.clan_members cm
  where cm.user_id=p_user_id and cm.status='active' and cm.role in ('owner','officer')
  limit 1 for update;
  if actor_clan_id is null then raise exception 'NO_CLAN_PERMISSION'; end if;

  select w.id,w.clan_a,w.clan_b,w.status into war
  from public.clan_wars w where w.id=p_war_id for update;
  if war.id is null then raise exception 'WAR_NOT_FOUND'; end if;
  if war.status not in ('scheduled','active') then raise exception 'WAR_NOT_ACTIVE'; end if;
  if war.clan_a<>actor_clan_id and war.clan_b<>actor_clan_id then raise exception 'NO_CLAN_PERMISSION'; end if;

  update public.clan_wars set status='cancelled' where id=p_war_id;
  return jsonb_build_object('success',true,'war_id',p_war_id,'status','cancelled');
end;
$function$;

create or replace function public.participant_cancel_clan_war(p_war_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_cancel_clan_war(uid,p_war_id);
end;
$function$;

revoke all on function public.participant_create_clan_war(text) from public,anon;
revoke all on function public.participant_cancel_clan_war(uuid) from public,anon;
grant execute on function public.participant_create_clan_war(text) to authenticated;
grant execute on function public.participant_cancel_clan_war(uuid) to authenticated;
