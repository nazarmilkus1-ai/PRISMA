-- Participant-safe global search gateway.
CREATE OR REPLACE FUNCTION private.prisma_participant_global_search(
  p_user_id uuid,p_query text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare
  q text:=trim(coalesce(p_query,''));
  pattern text;
begin
  perform private.prisma_participant_require_access(p_user_id);

  if char_length(q)=0 then
    return jsonb_build_object(
      'players','[]'::jsonb,'clans','[]'::jsonb,'news','[]'::jsonb,
      'wiki','[]'::jsonb,'market','[]'::jsonb
    );
  end if;

  if char_length(q)>100 then q:=left(q,100); end if;
  pattern:='%'||replace(replace(replace(q,E'\\',E'\\\\'),'%','\%'),'_','\_')||'%';

  return jsonb_build_object(
    'players',coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select u.id,u.minecraft_nickname,u.platform::text as platform,u.rating,u.level,u.xp
        from public.users u
        where u.deleted_at is null
          and u.status='ACCEPTED'::public.application_status
          and not u.is_banned
          and (u.minecraft_nickname ilike pattern escape '\\' or u.platform::text ilike pattern escape '\\')
        order by u.rating desc nulls last,u.minecraft_nickname limit 10
      ) x
    ),'[]'::jsonb),
    'clans',coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select c.id,c.name,c.tag
        from public.clans c
        where c.deleted_at is null and c.status='active'
          and (c.name ilike pattern escape '\\' or coalesce(c.tag,'') ilike pattern escape '\\' or coalesce(c.description,'') ilike pattern escape '\\')
        order by c.rating desc nulls last,c.name limit 10
      ) x
    ),'[]'::jsonb),
    'news',coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select n.id,n.title
        from public.news n
        where n.is_published and (n.title ilike pattern escape '\\' or n.body ilike pattern escape '\\')
        order by n.published_at desc nulls last,n.created_at desc limit 10
      ) x
    ),'[]'::jsonb),
    'wiki',coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select w.id,w.slug,w.title
        from public.wiki_pages w
        where w.published and (w.title ilike pattern escape '\\' or coalesce(w.excerpt,'') ilike pattern escape '\\' or coalesce(w.content,'') ilike pattern escape '\\')
        order by w.updated_at desc nulls last,w.created_at desc limit 10
      ) x
    ),'[]'::jsonb),
    'market',coalesce((
      select jsonb_agg(to_jsonb(x)) from (
        select m.id,m.title,m.kind
        from public.market_listings m
        where m.status='ACTIVE' and (m.title ilike pattern escape '\\' or coalesce(m.description,'') ilike pattern escape '\\')
        order by m.created_at desc limit 10
      ) x
    ),'[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_global_search(p_query text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_global_search(uid,p_query);
end;
$function$;

revoke all on function public.participant_global_search(text) from public;
grant execute on function public.participant_global_search(text) to authenticated;