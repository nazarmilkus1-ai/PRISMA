-- PRISMA Wiki visibility levels: PUBLIC / MEMBER / STAFF.

begin;

alter table public.wiki_pages
  add column if not exists visibility text not null default 'PUBLIC';

update public.wiki_pages
set visibility = case when upper(category) = 'STAFF' then 'STAFF' else 'PUBLIC' end;

alter table public.wiki_pages
  drop constraint if exists wiki_pages_visibility_check;

alter table public.wiki_pages
  add constraint wiki_pages_visibility_check
  check (visibility in ('PUBLIC','MEMBER','STAFF'));

create index if not exists idx_wiki_pages_published_visibility_updated
  on public.wiki_pages (published, visibility, updated_at desc);

drop policy if exists wiki_public_select on public.wiki_pages;
create policy wiki_public_select
  on public.wiki_pages
  for select
  to anon, authenticated
  using (published = true and visibility = 'PUBLIC');

revoke select on table public.wiki_pages from anon, authenticated;

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
        select id,slug,title,excerpt,content,category,visibility,published,created_at,updated_at
        from public.wiki_pages
        where published=true
          and visibility='PUBLIC'
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

create or replace function public.participant_get_wiki(p_query text default '', p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  is_member boolean := false;
  is_staff boolean := false;
begin
  if actor_uid is null then
    return '[]'::jsonb;
  end if;

  select exists(
    select 1
    from public.users u
    where u.auth_user_id=actor_uid
      and u.deleted_at is null
      and u.status='ACCEPTED'::public.application_status
      and not u.is_banned
  )
  into is_member;

  select exists(
    select 1
    from public.admins a
    join public.users u on u.id=a.user_id
    where u.auth_user_id=actor_uid
      and u.deleted_at is null
  )
  into is_staff;

  return coalesce(
    (
      select jsonb_agg(to_jsonb(x) order by x.updated_at desc nulls last, x.created_at desc)
      from (
        select w.id,w.slug,w.title,w.excerpt,w.content,w.category,w.visibility,w.published,w.created_at,w.updated_at
        from public.wiki_pages w
        where w.published=true
          and (
            w.visibility='PUBLIC'
            or (w.visibility='MEMBER' and (is_member or is_staff))
            or (w.visibility='STAFF' and is_staff)
          )
          and (
            coalesce(btrim(p_query),'')=''
            or position(lower(btrim(p_query)) in lower(coalesce(w.title,'')||' '||coalesce(w.excerpt,'')||' '||coalesce(w.content,'')))>0
          )
        order by w.updated_at desc nulls last, w.created_at desc
        limit greatest(1,least(coalesce(p_limit,100),100))
      ) x
    ),
    '[]'::jsonb
  );
end;
$function$;

revoke all on function public.get_public_wiki(text,integer) from public;
revoke all on function public.participant_get_wiki(text,integer) from public, anon;
grant execute on function public.get_public_wiki(text,integer) to anon, authenticated;
grant execute on function public.participant_get_wiki(text,integer) to authenticated;

create or replace function private.prisma_participant_global_search(
  p_user_id uuid,p_query text
)
returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare
  q text:=trim(coalesce(p_query,''));
  pattern text;
  is_staff boolean:=exists(
    select 1
    from public.admins a
    where a.user_id=p_user_id
  );
begin
  perform private.prisma_participant_require_access(p_user_id);

  if char_length(q)=0 then
    return jsonb_build_object(
      'players','[]'::jsonb,'clans','[]'::jsonb,'news','[]'::jsonb,
      'wiki','[]'::jsonb,'market','[]'::jsonb
    );
  end if;

  if char_length(q)>100 then q:=left(q,100); end if;
  pattern:='%'||replace(replace(replace(q,E'\\',E'\\\\'),'%','\\%'),'_','\\_')||'%';

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
        where w.published
          and (
            w.visibility='PUBLIC'
            or w.visibility='MEMBER'
            or (w.visibility='STAFF' and is_staff)
          )
          and (w.title ilike pattern escape '\\' or coalesce(w.excerpt,'') ilike pattern escape '\\' or coalesce(w.content,'') ilike pattern escape '\\')
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

commit;
