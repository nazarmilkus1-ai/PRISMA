create or replace function public.staff_set_event_result(
  p_event_id uuid,
  p_user_id uuid,
  p_score bigint default 0,
  p_placement integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_admin_id uuid;
  v_event_title text;
  v_event_slug text;
  v_user_nickname text;
  v_old_score bigint;
  v_old_placement integer;
begin
  select u.id into v_actor_id
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

  if p_event_id is null or p_user_id is null then raise exception 'TARGET_REQUIRED'; end if;
  if coalesce(p_score,0)<0 then raise exception 'INVALID_SCORE'; end if;
  if p_placement is not null and p_placement<1 then raise exception 'INVALID_PLACEMENT'; end if;

  select e.title,e.slug into v_event_title,v_event_slug
  from public.events e
  where e.id=p_event_id
  limit 1;
  if v_event_title is null then raise exception 'EVENT_NOT_FOUND'; end if;

  select u.minecraft_nickname into v_user_nickname
  from public.users u
  where u.id=p_user_id and u.deleted_at is null
  limit 1;
  if v_user_nickname is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  select ep.score,ep.placement into v_old_score,v_old_placement
  from public.event_participants ep
  where ep.event_id=p_event_id and ep.user_id=p_user_id
  for update;
  if not found then raise exception 'PLAYER_NOT_REGISTERED'; end if;

  update public.event_participants
  set score=coalesce(p_score,0), placement=p_placement
  where event_id=p_event_id and user_id=p_user_id;

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  select
    v_actor_id,u.telegram_id,'EVENT_RESULT_SET','event_participant',p_user_id,
    jsonb_build_object('event_id',p_event_id,'score',v_old_score,'placement',v_old_placement),
    jsonb_build_object('event_id',p_event_id,'score',coalesce(p_score,0),'placement',p_placement)
  from public.users u
  where u.id=v_actor_id
  limit 1;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  select
    u.id,u.telegram_id,'telegram','EVENT',
    'Результат события',
    'Для события "'||v_event_title||'" опубликован результат.'||
      case when p_placement is not null then ' Место: #'||p_placement||'.' else '' end||
      ' Результат: '||coalesce(p_score,0)||'.',
    jsonb_build_object(
      'event_id',p_event_id,
      'slug',v_event_slug,
      'score',coalesce(p_score,0),
      'placement',p_placement,
      'source','admin_panel'
    ),
    'pending',now()
  from public.users u
  where u.id=p_user_id and u.deleted_at is null
    and u.status='ACCEPTED'::public.application_status
    and not u.is_banned;

  return jsonb_build_object(
    'success',true,
    'event_id',p_event_id,
    'user_id',p_user_id,
    'score',coalesce(p_score,0),
    'placement',p_placement
  );
end;
$function$;