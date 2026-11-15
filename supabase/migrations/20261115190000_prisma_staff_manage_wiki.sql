-- Staff mutation gateway for Wiki pages (the panel must not write wiki_pages directly).
create or replace function public.staff_manage_wiki(
  p_action text,
  p_page_id uuid default null,
  p_slug text default null,
  p_title text default null,
  p_excerpt text default null,
  p_content text default null,
  p_category text default null,
  p_published boolean default null,
  p_visibility text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid;
  action text := upper(trim(coalesce(p_action,'')));
  vis text := upper(trim(coalesce(p_visibility,'')));
  page public.wiki_pages%rowtype;
begin
  select u.id into actor_id
  from public.users u
  join public.admins a on a.user_id=u.id
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if actor_id is null then raise exception 'ADMIN_PROFILE_NOT_LINKED'; end if;

  if not exists (
    select 1 from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id and p.key='wiki.manage'
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if action not in ('CREATE','UPDATE','DELETE') then raise exception 'INVALID_ACTION'; end if;
  if vis <> '' and vis not in ('PUBLIC','MEMBER','STAFF') then raise exception 'INVALID_VISIBILITY'; end if;

  if action = 'CREATE' then
    if p_slug is null or p_slug !~ '^[a-z0-9-]{1,120}$' then raise exception 'INVALID_SLUG'; end if;
    if p_title is null or char_length(trim(p_title)) not between 2 and 200 then raise exception 'INVALID_TITLE'; end if;
    if p_content is null or char_length(trim(p_content)) = 0 then raise exception 'INVALID_CONTENT'; end if;
    insert into public.wiki_pages(slug,title,excerpt,content,category,published,visibility)
    values (p_slug, trim(p_title), nullif(trim(coalesce(p_excerpt,'')),''), trim(p_content),
            upper(trim(coalesce(nullif(p_category,''),'GUIDE'))), coalesce(p_published,false), coalesce(nullif(vis,''),'PUBLIC'))
    returning * into page;
    return jsonb_build_object('success',true,'id',page.id,'page',to_jsonb(page));
  end if;

  if p_page_id is null then raise exception 'INVALID_PAGE'; end if;
  select * into page from public.wiki_pages where id=p_page_id for update;
  if not found then raise exception 'PAGE_NOT_FOUND'; end if;

  if action = 'DELETE' then
    delete from public.wiki_pages where id=p_page_id;
    return jsonb_build_object('success',true,'id',p_page_id);
  end if;

  update public.wiki_pages set
    title = coalesce(nullif(trim(coalesce(p_title,'')),''), title),
    excerpt = case when p_excerpt is null then excerpt else nullif(trim(p_excerpt),'') end,
    content = coalesce(nullif(trim(coalesce(p_content,'')),''), content),
    category = coalesce(nullif(upper(trim(coalesce(p_category,''))),''), category),
    published = coalesce(p_published, published),
    visibility = coalesce(nullif(vis,''), visibility),
    updated_at = now()
  where id=p_page_id
  returning * into page;
  return jsonb_build_object('success',true,'id',page.id,'page',to_jsonb(page));
end;
$function$;

revoke all on function public.staff_manage_wiki(text,uuid,text,text,text,text,text,boolean,text) from public,anon;
grant execute on function public.staff_manage_wiki(text,uuid,text,text,text,text,text,boolean,text) to authenticated;
