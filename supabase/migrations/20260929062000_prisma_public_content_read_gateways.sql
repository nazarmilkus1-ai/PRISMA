-- Public content read gateways.
-- Client roles intentionally have no direct SELECT on public tables after the
-- default privilege lockdown. Public web reads must cross explicit RPC gateways.

begin;

create or replace function public.get_public_news(p_limit integer default 20)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.published_at desc nulls last, x.created_at desc)
      from (
        select id,title,body,kind,published_at,created_at
        from public.news
        where is_published=true
        order by published_at desc nulls last, created_at desc
        limit greatest(1,least(coalesce(p_limit,20),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_clans(p_limit integer default 50)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.rating desc, x.points desc, x.name asc)
      from (
        select id,name,tag,description,rating,points,level,xp,wins,losses,color,avatar_url,created_at
        from public.clans
        where deleted_at is null and status='active'
        order by rating desc, points desc, name asc
        limit greatest(1,least(coalesce(p_limit,50),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_seasons(p_limit integer default 30)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.starts_at desc nulls last, x.created_at desc)
      from (
        select id,name,slug,status,starts_at,ends_at,created_at
        from public.seasons
        order by starts_at desc nulls last, created_at desc
        limit greatest(1,least(coalesce(p_limit,30),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_events(p_limit integer default 50)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.starts_at desc nulls last, x.created_at desc)
      from (
        select id,slug,title,description,status,starts_at,ends_at,registration_deadline,max_participants,reward_config,created_at
        from public.events
        where status in ('published','scheduled','live','finished')
        order by starts_at desc nulls last, created_at desc
        limit greatest(1,least(coalesce(p_limit,50),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_wiki(p_query text default '', p_limit integer default 100)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.updated_at desc nulls last, x.created_at desc)
      from (
        select id,slug,title,excerpt,content,category,published,created_at,updated_at
        from public.wiki_pages
        where published=true
          and (
            coalesce(btrim(p_query),'')=''
            or position(lower(btrim(p_query)) in lower(coalesce(title,'')||' '||coalesce(excerpt,'')||' '||coalesce(content,'')))>0
          )
        order by updated_at desc nulls last, created_at desc
        limit greatest(1,least(coalesce(p_limit,100),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_media(p_limit integer default 60)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.published_at desc, x.created_at desc)
      from (
        select id,title,url,kind,description,published_at,created_at
        from public.media_items
        where published_at is not null and published_at<=now()
        order by published_at desc, created_at desc
        limit greatest(1,least(coalesce(p_limit,60),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

create or replace function public.get_public_awards(p_limit integer default 100)
returns jsonb
language sql
security definer
set search_path=''
as $function$
  select coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select id,season_id,name,description,kind,target_type,target_id,created_at
        from public.awards
        order by created_at desc
        limit greatest(1,least(coalesce(p_limit,100),100))
      ) x
    ),
    '[]'::jsonb
  );
$function$;

revoke all on function public.get_public_news(integer) from public;
revoke all on function public.get_public_clans(integer) from public;
revoke all on function public.get_public_seasons(integer) from public;
revoke all on function public.get_public_events(integer) from public;
revoke all on function public.get_public_wiki(text,integer) from public;
revoke all on function public.get_public_media(integer) from public;
revoke all on function public.get_public_awards(integer) from public;

grant execute on function public.get_public_news(integer) to anon,authenticated;
grant execute on function public.get_public_clans(integer) to anon,authenticated;
grant execute on function public.get_public_seasons(integer) to anon,authenticated;
grant execute on function public.get_public_events(integer) to anon,authenticated;
grant execute on function public.get_public_wiki(text,integer) to anon,authenticated;
grant execute on function public.get_public_media(integer) to anon,authenticated;
grant execute on function public.get_public_awards(integer) to anon,authenticated;

commit;
