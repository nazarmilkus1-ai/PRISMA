-- PRISMA v2: trusted Telegram staff read adapters.
-- Keep bot admin reads behind service-role-only bot_* functions.

create or replace function public.bot_list_pending_applications(
  p_admin_tg_id bigint,
  p_limit integer default 10
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  lim integer:=greatest(1,least(coalesce(p_limit,10),100));
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if not public.bot_check_admin_permission(p_admin_tg_id,'application.view') then raise exception 'PERMISSION_DENIED'; end if;
  return coalesce((
    select json_agg(x order by (x->>'created_at')::timestamptz asc)
    from (
      select json_build_object(
        'id',a.id,'application_no',a.application_no,'user_id',a.user_id,
        'full_name',a.full_name,'age',a.age,'nickname',a.nickname,
        'platform',a.platform,'status',a.status,'created_at',a.created_at
      ) x
      from public.applications a
      where a.status='PENDING' and not a.is_archived
      order by a.created_at asc
      limit lim
    ) rows_data
  ),'[]'::json);
end;
$function$;

revoke all on function public.bot_list_pending_applications(bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_list_pending_applications(bigint,integer) to service_role;

create or replace function public.bot_list_open_reports(
  p_admin_tg_id bigint,
  p_limit integer default 15
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  lim integer:=greatest(1,least(coalesce(p_limit,15),100));
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if not public.bot_check_admin_permission(p_admin_tg_id,'report.view') then raise exception 'PERMISSION_DENIED'; end if;
  return coalesce((
    select json_agg(x order by (x->>'created_at')::timestamptz asc)
    from (
      select json_build_object(
        'id',r.id,'ticket_no',r.ticket_no,'user_id',r.user_id,'type',r.type,
        'target_nickname',r.target_nickname,'description',r.description,
        'status',r.status,'priority',r.priority,'category',r.category,
        'created_at',r.created_at,'assigned_to',r.assigned_to
      ) x
      from public.reports r
      where r.status in ('OPEN','IN_REVIEW')
      order by r.created_at asc
      limit lim
    ) rows_data
  ),'[]'::json);
end;
$function$;

revoke all on function public.bot_list_open_reports(bigint,integer) from public,anon,authenticated;
grant execute on function public.bot_list_open_reports(bigint,integer) to service_role;

create or replace function public.bot_search_players(
  p_admin_tg_id bigint,
  p_query text,
  p_limit integer default 10
)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  q text:=btrim(coalesce(p_query,''));
  lim integer:=greatest(1,least(coalesce(p_limit,10),50));
begin
  if p_admin_tg_id is null then raise exception 'INVALID_TELEGRAM_ID'; end if;
  if not public.bot_check_admin_permission(p_admin_tg_id,'player.view') then raise exception 'PERMISSION_DENIED'; end if;
  if q='' then raise exception 'INVALID_QUERY'; end if;

  return coalesce((
    select json_agg(x order by (x->>'minecraft_nickname') asc nulls last)
    from (
      select json_build_object(
        'id',u.id,'telegram_id',u.telegram_id,'telegram_username',u.telegram_username,
        'minecraft_nickname',u.minecraft_nickname,'status',u.status,'is_whitelisted',u.is_whitelisted,
        'rating',u.rating,'activity_score',u.activity_score,'level',u.level,'xp',u.xp,
        'warning_count',u.warning_count,'is_banned',u.is_banned,'is_muted',u.is_muted,
        'last_seen_at',u.last_seen_at,'clan_id',u.clan_id
      ) x,u.minecraft_nickname
      from public.users u
      where u.deleted_at is null
        and (
          u.minecraft_nickname ilike '%'||q||'%'
          or u.telegram_username ilike '%'||q||'%'
          or u.telegram_id::text=q
        )
      order by u.minecraft_nickname asc nulls last
      limit lim
    ) rows_data
  ),'[]'::json);
end;
$function$;

revoke all on function public.bot_search_players(bigint,text,integer) from public,anon,authenticated;
grant execute on function public.bot_search_players(bigint,text,integer) to service_role;
