-- Member-only read gateways for market and timeline data.

create or replace function private.prisma_participant_get_market(p_user_id uuid,p_kind text default null,p_query text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare q text:=trim(coalesce(p_query,''));
begin
  perform private.prisma_participant_require_access(p_user_id);
  if length(q)>64 then q:=left(q,64); end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select ml.id,ml.seller_id,ml.kind,ml.title,ml.description,ml.terms,ml.price_text,ml.status,ml.created_at,ml.updated_at,ml.expires_at,
             u.minecraft_nickname
      from public.market_listings ml
      join public.users u on u.id=ml.seller_id
      where ml.status='ACTIVE'
        and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
        and (nullif(trim(coalesce(p_kind,'')),'') is null or ml.kind=trim(p_kind))
        and (q='' or ml.title ilike '%'||q||'%' or ml.description ilike '%'||q||'%')
      order by ml.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),200))
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_get_market(p_kind text default null,p_query text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_market(uid,p_kind,p_query,p_limit);
end;
$function$;

revoke all on function public.participant_get_market(text,text,integer) from public,anon;
grant execute on function public.participant_get_market(text,text,integer) to authenticated;

create or replace function private.prisma_participant_get_timeline(p_user_id uuid,p_limit integer default 60)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.occurred_at desc)
    from (
      select te.id,te.kind,te.title,te.body,te.occurred_at,u.minecraft_nickname,c.name as clan_name,c.tag as clan_tag
      from public.timeline_events te
      left join public.users u on u.id=te.actor_user_id
      left join public.clans c on c.id=te.clan_id and c.deleted_at is null and c.status='active'
      order by te.occurred_at desc
      limit greatest(1,least(coalesce(p_limit,60),200))
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_get_timeline(p_limit integer default 60)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_timeline(uid,p_limit);
end;
$function$;

revoke all on function public.participant_get_timeline(integer) from public,anon;
grant execute on function public.participant_get_timeline(integer) to authenticated;
