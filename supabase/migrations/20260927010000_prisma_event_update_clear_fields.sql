drop function if exists public.staff_manage_event(text,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,integer,jsonb);

create function public.staff_manage_event(
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
  p_reward_config jsonb default '{}'::jsonb,
  p_clear_description boolean default false,
  p_clear_starts_at boolean default false,
  p_clear_ends_at boolean default false,
  p_clear_registration_deadline boolean default false,
  p_clear_max_participants boolean default false
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
  v_new_status text;
  v_new_starts timestamptz;
  v_new_ends timestamptz;
  v_new_deadline timestamptz;
  v_new_max integer;
  v_actor_tg_id bigint;
begin
  select u.id,u.telegram_id into v_actor_id,v_actor_tg_id
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
      slug,title,description,status,starts_at,ends_at,registration_deadline,max_participants,reward_config,created_by
    ) values(
      v_slug,v_title,nullif(v_description,''),v_status,p_starts_at,p_ends_at,p_registration_deadline,
      p_max_participants,coalesce(p_reward_config,'{}'::jsonb),v_admin_id
    )
    returning id into v_event_id;

    insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,new_data)
    values(v_actor_id,v_actor_tg_id,'EVENT_CREATED','event',v_event_id,
      jsonb_build_object('slug',v_slug,'title',v_title,'status',v_status));
    return jsonb_build_object('success',true,'event_id',v_event_id,'action','CREATE');
  end if;

  select * into v_old from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if v_action='CANCEL' then
    if v_old.status='finished' then raise exception 'EVENT_ALREADY_FINISHED'; end if;
    update public.events set status='cancelled',updated_at=now() where id=p_event_id;
  else
    v_new_status:=case when p_status is null then v_old.status else v_status end;
    v_new_starts:=case
      when p_clear_starts_at then null
      when p_starts_at is null then v_old.starts_at
      else p_starts_at
    end;
    v_new_ends:=case
      when p_clear_ends_at then null
      when p_ends_at is null then v_old.ends_at
      else p_ends_at
    end;
    v_new_deadline:=case
      when p_clear_registration_deadline then null
      when p_registration_deadline is null then v_old.registration_deadline
      else p_registration_deadline
    end;
    v_new_max:=case
      when p_clear_max_participants then null
      when p_max_participants is null then v_old.max_participants
      else p_max_participants
    end;

    if p_slug is not null and v_slug !~ '^[a-z0-9][a-z0-9._-]{1,119}$' then raise exception 'INVALID_SLUG'; end if;
    if p_title is not null and char_length(v_title) not between 2 and 160 then raise exception 'INVALID_TITLE'; end if;
    if p_description is not null and char_length(v_description)>5000 then raise exception 'INVALID_DESCRIPTION'; end if;
    if v_new_status not in ('draft','scheduled','live','finished','cancelled') then raise exception 'INVALID_STATUS'; end if;
    if v_new_max is not null and v_new_max<1 then raise exception 'INVALID_MAX_PARTICIPANTS'; end if;
    if v_new_max is not null and v_new_max < (select count(*) from public.event_participants where event_id=p_event_id)
      then raise exception 'MAX_BELOW_CURRENT_PARTICIPANTS'; end if;
    if v_new_starts is not null and v_new_ends is not null and v_new_ends<=v_new_starts then raise exception 'INVALID_DATES'; end if;
    if v_new_deadline is not null and v_new_starts is not null and v_new_deadline>v_new_starts then raise exception 'INVALID_REGISTRATION_DEADLINE'; end if;

    if v_old.status='draft' and v_new_status not in ('draft','scheduled','cancelled') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    if v_old.status='scheduled' and v_new_status not in ('scheduled','live','cancelled') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    if v_old.status='live' and v_new_status not in ('live','finished','cancelled') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    if v_old.status in ('finished','cancelled') and v_new_status<>v_old.status then raise exception 'INVALID_STATUS_TRANSITION'; end if;

    update public.events
    set slug=case when p_slug is null then slug else v_slug end,
        title=case when p_title is null then title else v_title end,
        description=case when p_clear_description then null when p_description is null then description else nullif(v_description,'') end,
        status=v_new_status,
        starts_at=v_new_starts,
        ends_at=v_new_ends,
        registration_deadline=v_new_deadline,
        max_participants=v_new_max,
        reward_config=case when p_reward_config is null then reward_config else p_reward_config end,
        updated_at=now()
    where id=p_event_id;
  end if;

  insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
  values(
    v_actor_id,v_actor_tg_id,
    case when v_action='CANCEL' then 'EVENT_CANCELLED' else 'EVENT_UPDATED' end,
    'event',p_event_id,to_jsonb(v_old),
    (select to_jsonb(e) from public.events e where e.id=p_event_id)
  );

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data,status,available_at)
  select
    u.id,u.telegram_id,'telegram','EVENT',
    case when v_action='CANCEL' then 'Событие отменено' else 'Событие обновлено' end,
    case when v_action='CANCEL'
      then 'Событие "'||v_old.title||'" было отменено.'
      else 'Событие "'||coalesce(p_title,v_old.title)||'" было обновлено.'
    end,
    jsonb_build_object('event_id',p_event_id,'slug',coalesce(p_slug,v_old.slug),'action',v_action,'source','admin_panel'),
    'pending',now()
  from public.event_participants ep
  join public.users u on u.id=ep.user_id
  where ep.event_id=p_event_id and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status and not u.is_banned;

  return jsonb_build_object('success',true,'event_id',p_event_id,'action',v_action);
end;
$function$;

revoke execute on function public.staff_manage_event(text,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,integer,jsonb,boolean,boolean,boolean,boolean,boolean) from public,anon;
grant execute on function public.staff_manage_event(text,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,integer,jsonb,boolean,boolean,boolean,boolean,boolean) to authenticated;