create or replace function public.staff_manage_event(
  p_action text,
  p_event_id uuid default null,
  p_slug text default null,
  p_title text default null,
  p_description text default null,
  p_status text default null,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_registration_deadline timestamptz default null,
  p_max_participants integer default null,
  p_reward_config jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor_id uuid;
  v_admin_id uuid;
  v_old public.events%rowtype;
  v_event_id uuid;
  v_action text:=upper(trim(coalesce(p_action,'')));
  v_slug text:=lower(trim(coalesce(p_slug,'')));
  v_title text:=trim(coalesce(p_title,''));
  v_description text:=trim(coalesce(p_description,''));
  v_status text:=lower(trim(coalesce(p_status,'')));
  v_actor_tg_id bigint;
  v_actor_name text;
begin
  select u.id,u.telegram_id,u.minecraft_nickname
    into v_actor_id,v_actor_tg_id,v_actor_name
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;

  if v_actor_id is null then raise exception 'ADMIN_PROFILE_NOT_LINKED'; end if;

  select a.id into v_admin_id
  from public.admins a
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where a.user_id=v_actor_id and p.key='event.manage'
  limit 1;

  if v_admin_id is null then raise exception 'FORBIDDEN'; end if;

  if v_action not in ('CREATE','UPDATE','CANCEL') then raise exception 'INVALID_ACTION'; end if;

  if v_action='CREATE' then
    if v_slug !~ '^[a-z0-9][a-z0-9._-]{1,119}$' then raise exception 'INVALID_SLUG'; end if;
    if char_length(v_title) not between 2 and 160 then raise exception 'INVALID_TITLE'; end if;
    if char_length(v_description)>5000 then raise exception 'INVALID_DESCRIPTION'; end if;
    if v_status not in ('draft','scheduled','live','finished','cancelled') then raise exception 'INVALID_STATUS'; end if;
    if p_max_participants is not null and p_max_participants<1 then raise exception 'INVALID_MAX_PARTICIPANTS'; end if;
    if p_starts_at is not null and p_ends_at is not null and p_ends_at<=p_starts_at then raise exception 'INVALID_DATES'; end if;
    if p_registration_deadline is not null and p_starts_at is not null and p_registration_deadline>p_starts_at then raise exception 'INVALID_REGISTRATION_DEADLINE'; end if;

    insert into public.events(
      slug,title,description,status,starts_at,ends_at,registration_deadline,
      max_participants,reward_config,created_by
    ) values(
      v_slug,v_title,v_description,v_status,p_starts_at,p_ends_at,p_registration_deadline,
      p_max_participants,coalesce(p_reward_config,'{}'::jsonb),v_admin_id
    )
    returning id into v_event_id;

    insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
    values(
      v_actor_id,v_actor_tg_id,'EVENT_CREATED','event',v_event_id,
      jsonb_build_object('slug',v_slug,'title',v_title,'status',v_status)
    );

    return jsonb_build_object('success',true,'event_id',v_event_id,'action','CREATE');
  end if;

  select * into v_old from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if v_action='CANCEL' then
    update public.events set status='cancelled',updated_at=now() where id=p_event_id;
  else
    if p_slug is not null then
      if v_slug !~ '^[a-z0-9][a-z0-9._-]{1,119}$' then raise exception 'INVALID_SLUG'; end if;
    end if;
    if p_title is not null and char_length(v_title) not between 2 and 160 then raise exception 'INVALID_TITLE'; end if;
    if p_description is not null and char_length(v_description)>5000 then raise exception 'INVALID_DESCRIPTION'; end if;
    if p_status is not null and v_status not in ('draft','scheduled','live','finished','cancelled') then raise exception 'INVALID_STATUS'; end if;
    if p_max_participants is not null and p_max_participants<1 then raise exception 'INVALID_MAX_PARTICIPANTS'; end if;
    if p_starts_at is not null and p_ends_at is not null and p_ends_at<=p_starts_at then raise exception 'INVALID_DATES'; end if;
    if p_registration_deadline is not null and p_starts_at is not null and p_registration_deadline>p_starts_at then raise exception 'INVALID_REGISTRATION_DEADLINE'; end if;

    update public.events
    set slug=case when p_slug is null then slug else v_slug end,
        title=case when p_title is null then title else v_title end,
        description=case when p_description is null then description else v_description end,
        status=case when p_status is null then status else v_status end,
        starts_at=case when p_starts_at is null then starts_at else p_starts_at end,
        ends_at=case when p_ends_at is null then ends_at else p_ends_at end,
        registration_deadline=case when p_registration_deadline is null then registration_deadline else p_registration_deadline end,
        max_participants=case when p_max_participants is null then max_participants else p_max_participants end,
        reward_config=case when p_reward_config is null then reward_config else p_reward_config end,
        updated_at=now()
    where id=p_event_id;
  end if;

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
  values(
    v_actor_id,v_actor_tg_id,
    case when v_action='CANCEL' then 'EVENT_CANCELLED' else 'EVENT_UPDATED' end,
    'event',p_event_id,
    to_jsonb(v_old),
    (select to_jsonb(e) from public.events e where e.id=p_event_id)
  );

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    u.id,u.telegram_id,'telegram','EVENT',
    case when v_action='CANCEL' then 'Событие отменено' else 'Событие обновлено' end,
    case when v_action='CANCEL'
      then 'Событие "'||v_old.title||'" было отменено.'
      else 'Событие "'||coalesce(p_title,v_old.title)||'" было обновлено.'
    end,
    jsonb_build_object(
      'event_id',p_event_id,
      'slug',coalesce(p_slug,v_old.slug),
      'action',v_action,
      'source','admin_panel'
    ),
    'pending',now()
  from public.event_participants ep
  join public.users u on u.id=ep.user_id
  where ep.event_id=p_event_id
    and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned;

  return jsonb_build_object('success',true,'event_id',p_event_id,'action',v_action);
end;
$function$;

revoke execute on function public.staff_manage_event(text,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,integer,jsonb) from public,anon;
grant execute on function public.staff_manage_event(text,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,integer,jsonb) to authenticated;