-- Paginated raw analytics records. Aggregate graphs stay in staff_get_analytics;
-- large tables load real rows on demand for the selected period.

create or replace function public.staff_get_analytics_details(
  p_period text default '30d',
  p_kind text default 'chat',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  period_value text := lower(trim(coalesce(p_period,'30d')));
  kind_value text := lower(trim(coalesce(p_kind,'chat')));
  since_at timestamptz;
  lim integer := greatest(1,least(coalesce(p_limit,50),100));
  off integer := greatest(0,least(coalesce(p_offset,0),1000000));
  total_rows bigint := 0;
  rows_data jsonb := '[]'::jsonb;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'analytics.view')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  if period_value not in ('24h','7d','30d','all') then
    raise exception 'INVALID_PERIOD';
  end if;
  if kind_value not in ('applications','chat','audit') then
    raise exception 'INVALID_ANALYTICS_DETAIL_KIND';
  end if;

  since_at := case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null
  end;

  if kind_value='applications' then
    select count(*) into total_rows
    from public.applications a
    where not a.is_archived
      and (since_at is null or a.created_at>=since_at);

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb)
    into rows_data
    from (
      select a.id,a.application_no,a.user_id,a.status,a.full_name,a.age,
             a.nickname,a.platform,a.birth_date,a.goal,a.about,a.discovery_source,
             a.created_at,a.updated_at,a.reviewed_at,a.reviewed_by_name,
             a.rejection_reason,u.telegram_id,u.telegram_username
      from public.applications a
      left join public.users u on u.id=a.user_id
      where not a.is_archived
        and (since_at is null or a.created_at>=since_at)
      order by a.created_at desc,a.id
      limit lim offset off
    ) x;
  elsif kind_value='chat' then
    select count(*) into total_rows
    from public.chat_logs c
    where since_at is null or c.created_at>=since_at;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb)
    into rows_data
    from (
      select c.id,c.user_id,c.message,c.world,c.created_at,
             u.minecraft_nickname,u.telegram_username,u.full_name
      from public.chat_logs c
      left join public.users u on u.id=c.user_id
      where since_at is null or c.created_at>=since_at
      order by c.created_at desc,c.id
      limit lim offset off
    ) x;
  else
    select count(*) into total_rows
    from public.audit_logs a
    where since_at is null or a.created_at>=since_at;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb)
    into rows_data
    from (
      select a.id,a.actor_user_id,a.actor_tg_id,a.action,
             a.target_type,a.target_id,a.created_at,
             coalesce(u.telegram_username,u.minecraft_nickname,u.full_name,a.actor_tg_id::text) as actor_name
      from public.audit_logs a
      left join public.users u on u.id=a.actor_user_id
      where since_at is null or a.created_at>=since_at
      order by a.created_at desc,a.id
      limit lim offset off
    ) x;
  end if;

  return jsonb_build_object(
    'kind',kind_value,'period',period_value,'rows',rows_data,
    'total',total_rows,'limit',lim,'offset',off
  );
end;
$function$;

revoke all on function public.staff_get_analytics_details(text,text,integer,integer) from public,anon;
grant execute on function public.staff_get_analytics_details(text,text,integer,integer) to authenticated;

 
-- Aggregate admin actions separately so all-time tables do not count only the
-- truncated raw audit payload returned for charts.
create or replace function public.staff_get_analytics_admin_summary(p_period text default '30d')
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  period_value text := lower(trim(coalesce(p_period,'30d')));
  since_at timestamptz;
  result jsonb;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'analytics.view')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;
  if period_value not in ('24h','7d','30d','all') then raise exception 'INVALID_PERIOD'; end if;

  since_at := case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null
  end;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total desc,x.actor asc),'[]'::jsonb)
  into result
  from (
    select
      u.telegram_id,
      coalesce(case when u.telegram_username is not null then '@'||u.telegram_username end,
               u.minecraft_nickname,u.full_name,u.telegram_id::text) as actor,
      r.name as role,
      count(al.id)::integer as total,
      count(al.id) filter (where
        left(lower(coalesce(al.action,'')),12) in ('application.','application_')
      )::integer as applications,
      count(al.id) filter (where
        left(lower(coalesce(al.action,'')),7) in ('report.','report_')
      )::integer as reports,
      count(al.id) filter (where
        left(lower(coalesce(al.action,'')),11) in ('moderation.','moderation_')
      )::integer as moderation,
      count(al.id) filter (where
        left(lower(coalesce(al.action,'')),6) in ('admin.','staff.')
        or left(lower(coalesce(al.action,'')),5)='role.'
        or left(lower(coalesce(al.action,'')),9)='settings.'
      )::integer as management,
      count(al.id) filter (where
        left(lower(coalesce(al.action,'')),5)='auth.'
        or left(lower(coalesce(al.action,'')),6)='login.'
        or left(lower(coalesce(al.action,'')),4)='mfa.'
      )::integer as auth,
      count(al.id) filter (where al.id is not null and not (
        left(lower(coalesce(al.action,'')),12) in ('application.','application_')
        or left(lower(coalesce(al.action,'')),7) in ('report.','report_')
        or left(lower(coalesce(al.action,'')),11) in ('moderation.','moderation_')
        or left(lower(coalesce(al.action,'')),6) in ('admin.','staff.')
        or left(lower(coalesce(al.action,'')),5)='role.'
        or left(lower(coalesce(al.action,'')),9)='settings.'
        or left(lower(coalesce(al.action,'')),5)='auth.'
        or left(lower(coalesce(al.action,'')),6)='login.'
        or left(lower(coalesce(al.action,'')),4)='mfa.'
      ))::integer as other,
      (array_agg(al.action order by al.created_at desc,al.id desc) filter (where al.id is not null))[1] as last_action,
      max(al.created_at) as last_action_at
    from public.admins a
    join public.users u on u.id=a.user_id and u.deleted_at is null
    join public.roles r on r.id=a.role_id
    left join public.audit_logs al
      on (al.actor_user_id=u.id or (u.telegram_id is not null and al.actor_tg_id=u.telegram_id))
      and (since_at is null or al.created_at>=since_at)
    group by u.telegram_id,u.telegram_username,u.minecraft_nickname,u.full_name,r.name
  ) x;

  return result;
end;
$function$;

revoke all on function public.staff_get_analytics_admin_summary(text) from public,anon;
grant execute on function public.staff_get_analytics_admin_summary(text) to authenticated;
