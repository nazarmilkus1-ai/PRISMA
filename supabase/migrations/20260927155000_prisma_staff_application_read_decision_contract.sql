-- PRISMA v2: authenticated staff application reads and decision metadata.

create or replace function public.staff_list_applications(
  p_status text default 'PENDING',
  p_search text default '',
  p_limit integer default 100
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  filter_status text := upper(trim(coalesce(p_status,'PENDING')));
  q text := btrim(coalesce(p_search,''));
  lim integer := greatest(1, least(coalesce(p_limit,100),500));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='application.view'
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  if filter_status not in ('ALL','PENDING','ACCEPTED','REJECTED') then raise exception 'INVALID_STATUS'; end if;

  return coalesce((
    select json_agg(row_data order by created_sort desc)
    from (
      select json_build_object(
        'id',a.id,'application_no',a.application_no,'full_name',a.full_name,'age',a.age,
        'nickname',a.nickname,'platform',a.platform,'discovery_source',a.discovery_source,
        'status',a.status,'created_at',a.created_at,'reviewed_at',a.reviewed_at
      ) as row_data, a.created_at as created_sort
      from public.applications a
      where not a.is_archived
        and (filter_status='ALL' or a.status::text=filter_status)
        and (q='' or a.nickname ilike '%'||q||'%' or a.full_name ilike '%'||q||'%' or a.application_no::text=q)
      order by a.created_at desc
      limit lim
    ) rows_data
  ), '[]'::json);
end;
$function$;

revoke all on function public.staff_list_applications(text,text,integer) from public,anon;
grant execute on function public.staff_list_applications(text,text,integer) to authenticated;

create or replace function public.staff_get_application(p_application_id uuid)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  application_data json;
  history_data json;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  join public.role_permissions rp on rp.role_id=a.role_id
  join public.permissions p on p.id=rp.permission_id
  where u.auth_user_id=actor_uid and u.deleted_at is null and p.key='application.view'
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  select json_build_object(
    'id',a.id,'application_no',a.application_no,'full_name',a.full_name,'age',a.age,'nickname',a.nickname,
    'platform',a.platform,'discovery_source',a.discovery_source,'status',a.status,
    'rejection_reason',a.rejection_reason,'created_at',a.created_at,'updated_at',a.updated_at,
    'reviewed_at',a.reviewed_at,'reviewed_by_tg_id',a.reviewed_by_tg_id,'reviewed_by_name',a.reviewed_by_name,
    'staff_notes',a.staff_notes,'cooldown_until',a.cooldown_until,'birth_date',a.birth_date,
    'goal',a.goal,'about',a.about,'user_id',a.user_id,
    'users',case when u.id is null then null else json_build_object(
      'id',u.id,'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,'first_name',u.first_name,
      'last_name',u.last_name,'full_name',u.full_name,'minecraft_nickname',u.minecraft_nickname,'platform',u.platform,
      'status',u.status,'is_whitelisted',u.is_whitelisted,'is_banned',u.is_banned,'is_muted',u.is_muted,
      'rating',u.rating,'activity_score',u.activity_score,'last_seen_at',u.last_seen_at,'created_at',u.created_at
    ) end
  ) into application_data
  from public.applications a
  left join public.users u on u.id=a.user_id
  where a.id=p_application_id;

  if application_data is null then raise exception 'APPLICATION_NOT_FOUND'; end if;

  select coalesce(json_agg(
    json_build_object('id',h.id,'action',h.action,'actor_tg_id',h.actor_tg_id,'reason',h.reason,'created_at',h.created_at)
    order by h.created_at desc
  ),'[]'::json) into history_data
  from public.application_history h
  where h.application_id=p_application_id;

  return application_data::jsonb || jsonb_build_object('history',history_data)::jsonb;
end;
$function$;

revoke all on function public.staff_get_application(uuid) from public,anon;
grant execute on function public.staff_get_application(uuid) to authenticated;

create or replace function public.staff_decide_application(
  p_application_id uuid,
  p_action text,
  p_reason text default null
) returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_user_id uuid;
  result json;
  target_user_id uuid;
  target_tg_id bigint;
  application_no bigint;
  nickname text;
begin
  select u.id into actor_user_id
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if actor_user_id is null then raise exception 'STAFF_IDENTITY_NOT_FOUND'; end if;

  result:=private.prisma_decide_application(p_application_id,actor_user_id,p_action,p_reason);
  target_user_id:=(result->>'user_id')::uuid;

  select u.telegram_id into target_tg_id from public.users u where u.id=target_user_id;
  select a.application_no,a.nickname into application_no,nickname
  from public.applications a where a.id=p_application_id;

  return result::jsonb || jsonb_build_object(
    'target_telegram_id',target_tg_id,'application_no',application_no,'nickname',nickname
  );
end;
$function$;

revoke all on function public.staff_decide_application(uuid,text,text) from public,anon;
grant execute on function public.staff_decide_application(uuid,text,text) to authenticated;
