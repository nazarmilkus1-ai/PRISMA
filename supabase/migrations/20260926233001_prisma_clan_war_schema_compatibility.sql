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
    update public.clan_wars set status='cancelled' where id=p_war_id;
  else
    update public.clan_wars set status='scheduled',scheduled_at=now() where id=p_war_id;
  end if;
  select name,tag into actor_name,actor_tag from public.clans where id=actor_clan_id;
  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
  select p_user_id,u.telegram_id,
    case when action='ACCEPT' then 'CLAN_WAR_ACCEPTED' else 'CLAN_WAR_DECLINED' end,
    'clan_war',p_war_id,
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
  update public.clan_wars set status='cancelled' where id=p_war_id;
  insert into public.audit_logs(actor_user_id,action,target_type,target_id,new_data)
  values(p_user_id,'CLAN_WAR_CANCELLED','clan_war',p_war_id,jsonb_build_object('status','cancelled'));
  return jsonb_build_object('success',true,'war_id',p_war_id,'status','cancelled');
end;
$function$;