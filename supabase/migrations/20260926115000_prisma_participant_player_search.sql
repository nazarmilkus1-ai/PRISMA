-- Safe participant player directory/search gateway. Browser clients never receive direct users-table access.

create or replace function private.prisma_participant_search_players(
  p_user_id uuid,
  p_query text,
  p_limit integer default 100
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare q text := trim(coalesce(p_query,''));
begin
  perform private.prisma_participant_require_access(p_user_id);
  if length(q) > 64 then q := left(q,64); end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.rating desc, x.minecraft_nickname asc)
    from (
      select u.id,u.minecraft_nickname,u.telegram_username,u.platform,u.rating,u.activity_score,
             u.level,u.xp,u.last_seen_at,u.created_at,u.clan_id
      from public.users u
      where u.deleted_at is null
        and u.status='ACCEPTED'
        and not u.is_banned
        and u.minecraft_nickname is not null
        and (q='' or u.minecraft_nickname ilike '%'||q||'%')
      order by u.rating desc,u.minecraft_nickname asc
      limit greatest(1,least(coalesce(p_limit,100),300))
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_search_players(
  p_query text default '',
  p_limit integer default 100
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_search_players(uid,p_query,p_limit);
end;
$function$;

revoke all on function public.participant_search_players(text,integer) from public,anon;
grant execute on function public.participant_search_players(text,integer) to authenticated;
