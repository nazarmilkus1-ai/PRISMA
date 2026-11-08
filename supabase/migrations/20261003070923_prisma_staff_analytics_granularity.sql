-- Analytics granularity contract:
-- regular: day=hourly, week/month/all=days; detailed: selected period=hours.
-- CLI is not installed in this workspace, so this migration file mirrors the
-- already-tested database definition applied directly through Supabase.

CREATE OR REPLACE FUNCTION public.staff_get_analytics(p_days integer DEFAULT 30, p_chat_days integer DEFAULT 2, p_period text DEFAULT '30d'::text, p_detail boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_uid uuid:=(select auth.uid());
  actor_id uuid;
  period_value text:=case lower(trim(coalesce(p_period,'30d')))
    when '24h' then '24h' when '7d' then '7d' when '30d' then '30d' when 'all' then 'all'
    else case when coalesce(p_days,30)<=1 then '24h' when coalesce(p_days,30)<=7 then '7d' else '30d' end
  end;
  since_at timestamptz;
  applications json;
  chats json;
  ratings json;
  audits json;
  admins json;
  application_trend json;
  chat_activity json;
  admin_activity json;
  top_chat_users json;
  application_status json;
  unique_chat_players integer;
  total_admin_actions integer;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid
    and u.deleted_at is null
    and private.prisma_has_user_permission(u.id,'analytics.view')
  limit 1;
  if actor_id is null then raise exception 'PERMISSION_DENIED'; end if;

  since_at:=case period_value
    when '24h' then now()-interval '24 hours'
    when '7d' then now()-interval '7 days'
    when '30d' then now()-interval '30 days'
    else null
  end;

  select coalesce(json_object_agg(x.status,x.count),'{}'::json)
  into application_status
  from (
    select status::text as status,count(*)::integer as count
    from public.applications
    where (since_at is null or created_at>=since_at) and not is_archived
    group by status
  ) x;

  select count(distinct user_id)::integer into unique_chat_players
  from public.chat_logs
  where since_at is null or created_at>=since_at;

  select count(*)::integer into total_admin_actions
  from public.audit_logs
  where since_at is null or created_at>=since_at;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into applications
  from (
    select id,application_no,user_id,created_at,status,nickname,platform
    from public.applications
    where (since_at is null or created_at>=since_at) and not is_archived
    order by created_at desc
    limit 5000
  ) x;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into chats
  from (
    select c.id,c.user_id,c.message,c.world,c.created_at,
           u.minecraft_nickname,u.telegram_username,u.full_name
    from public.chat_logs c
    join public.users u on u.id=c.user_id
    where since_at is null or c.created_at>=since_at
    order by c.created_at desc
    limit 5000
  ) x;

  select coalesce(json_agg(to_jsonb(x) order by x.created_at desc),'[]'::json)
  into audits
  from (
    select al.id,al.actor_user_id,al.actor_tg_id,al.action,al.target_type,al.target_id,
           al.new_data,al.created_at,
           coalesce(u.telegram_username,u.minecraft_nickname,u.full_name,al.actor_tg_id::text) as actor_name
    from public.audit_logs al
    left join public.users u on u.id=al.actor_user_id
    where since_at is null or al.created_at>=since_at
    order by al.created_at desc
    limit 10000
  ) x;

  select coalesce(json_agg(to_jsonb(x)),'[]'::json)
  into ratings
  from (
    select pr.value
    from public.poll_ratings pr
    join public.polls p on p.id=pr.poll_id
    where p.kind='SERVER_RATING' and (since_at is null or pr.created_at>=since_at)
  ) x;

  select coalesce(json_agg(x),'[]'::json)
  into admins
  from (
    select json_build_object(
      'telegram_id',u.telegram_id,
      'telegram_username',u.telegram_username,
      'minecraft_nickname',u.minecraft_nickname,
      'full_name',u.full_name,
      'role',r.name
    ) x
    from public.admins a
    join public.users u on u.id=a.user_id and u.deleted_at is null
    join public.roles r on r.id=a.role_id
  ) x;

  if p_detail or period_value='24h' then
    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into application_trend
    from (
      select date_trunc('hour',g) bucket,count(a.id)::integer count
      from generate_series(
        date_trunc('hour',
          case
            when period_value='24h' then now()-interval '23 hours'
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.applications where not is_archived),now())
          end
        ),
        date_trunc('hour',now()),interval '1 hour'
      ) g
      left join public.applications a
        on a.created_at>=g and a.created_at<g+interval '1 hour' and not a.is_archived
      group by g
    ) x;

    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into chat_activity
    from (
      select date_trunc('hour',g) bucket,
             count(c.id)::integer messages,
             count(distinct c.user_id)::integer unique_players
      from generate_series(
        date_trunc('hour',
          case
            when period_value='24h' then now()-interval '23 hours'
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.chat_logs),now())
          end
        ),
        date_trunc('hour',now()),interval '1 hour'
      ) g
      left join public.chat_logs c
        on c.created_at>=g and c.created_at<g+interval '1 hour'
      group by g
    ) x;

    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into admin_activity
    from (
      select date_trunc('hour',g) bucket,
             count(al.id)::integer total_actions,
             count(distinct coalesce(al.actor_user_id::text,al.actor_tg_id::text))::integer active_admins
      from generate_series(
        date_trunc('hour',
          case
            when period_value='24h' then now()-interval '23 hours'
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.audit_logs),now())
          end
        ),
        date_trunc('hour',now()),interval '1 hour'
      ) g
      left join public.audit_logs al
        on al.created_at>=g and al.created_at<g+interval '1 hour'
      group by g
    ) x;
  else
    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into application_trend
    from (
      select date_trunc('day',g) bucket,count(a.id)::integer count
      from generate_series(
        date_trunc('day',
          case
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.applications where not is_archived),now())
          end
        ),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.applications a
        on a.created_at>=g and a.created_at<g+interval '1 day' and not a.is_archived
      group by g
    ) x;

    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into chat_activity
    from (
      select date_trunc('day',g) bucket,
             count(c.id)::integer messages,
             count(distinct c.user_id)::integer unique_players
      from generate_series(
        date_trunc('day',
          case
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.chat_logs),now())
          end
        ),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.chat_logs c
        on c.created_at>=g and c.created_at<g+interval '1 day'
      group by g
    ) x;

    select coalesce(json_agg(x order by x.bucket),'[]'::json)
    into admin_activity
    from (
      select date_trunc('day',g) bucket,
             count(al.id)::integer total_actions,
             count(distinct coalesce(al.actor_user_id::text,al.actor_tg_id::text))::integer active_admins
      from generate_series(
        date_trunc('day',
          case
            when period_value='7d' then now()-interval '6 days'
            when period_value='30d' then now()-interval '29 days'
            else coalesce((select min(created_at) from public.audit_logs),now())
          end
        ),
        date_trunc('day',now()),interval '1 day'
      ) g
      left join public.audit_logs al
        on al.created_at>=g and al.created_at<g+interval '1 day'
      group by g
    ) x;
  end if;

  select coalesce(json_agg(x order by x.messages desc,x.last_message_at desc),'[]'::json)
  into top_chat_users
  from (
    select
      c.user_id,
      coalesce(u.minecraft_nickname,u.telegram_username,u.full_name,c.user_id::text) as player,
      count(*)::integer messages,
      max(c.created_at) last_message_at
    from public.chat_logs c
    left join public.users u on u.id=c.user_id
    where since_at is null or c.created_at>=since_at
    group by c.user_id,coalesce(u.minecraft_nickname,u.telegram_username,u.full_name,c.user_id::text)
    order by messages desc,last_message_at desc
    limit 15
  ) x;

  return json_build_object(
    'period',period_value,
    'detail',coalesce(p_detail,false),
    'from',since_at,
    'to',now(),
    'application_status',application_status,
    'unique_chat_players',coalesce(unique_chat_players,0),
    'total_admin_actions',coalesce(total_admin_actions,0),
    'applications',applications,
    'chat',chats,
    'ratings',ratings,
    'audit',audits,
    'admins',admins,
    'application_trend',application_trend,
    'chat_activity',chat_activity,
    'admin_activity',admin_activity,
    'top_chat_users',top_chat_users
  );
end;
$function$


create or replace function public.staff_get_analytics(
  p_days integer default 30,
  p_chat_days integer default 2,
  p_period text default '30d'
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
begin
  return public.staff_get_analytics(p_days,p_chat_days,p_period,false);
end;
$function$;

revoke all on function public.staff_get_analytics(integer,integer,text,boolean) from public,anon;
grant execute on function public.staff_get_analytics(integer,integer,text,boolean) to authenticated;
revoke all on function public.staff_get_analytics(integer,integer,text) from public,anon;
grant execute on function public.staff_get_analytics(integer,integer,text) to authenticated;
