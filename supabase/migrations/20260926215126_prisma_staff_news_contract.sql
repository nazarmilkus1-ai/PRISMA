-- Canonical staff mutation contract for PRISMA news.

create or replace function public.staff_manage_news(
  p_action text,
  p_news_id uuid default null,
  p_title text default null,
  p_body text default null,
  p_kind text default null,
  p_is_published boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_id uuid;
  actor_admin_id uuid;
  actor_tg_id bigint;
  actor_name text;
  action text:=upper(trim(coalesce(p_action,'')));
  clean_kind text:=upper(trim(coalesce(p_kind,'')));
  existing public.news%rowtype;
  created public.news%rowtype;
  publish_state boolean;
begin
  select u.id,a.id,u.telegram_id,coalesce(u.full_name,u.minecraft_nickname,u.telegram_username,'Staff')
    into actor_id,actor_admin_id,actor_tg_id,actor_name
  from public.users u
  join public.admins a on a.user_id=u.id
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if actor_id is null then
    raise exception 'ADMIN_PROFILE_NOT_LINKED';
  end if;

  if not exists (
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id
      and p.key='news.manage'
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if action not in ('CREATE','UPDATE','ARCHIVE') then
    raise exception 'INVALID_ACTION';
  end if;

  if action='CREATE' then
    if p_title is null or char_length(trim(p_title)) not between 2 and 200 then
      raise exception 'INVALID_TITLE';
    end if;
    if p_body is null or char_length(trim(p_body)) not between 2 and 10000 then
      raise exception 'INVALID_BODY';
    end if;
    if clean_kind not in ('NEWS','UPDATE') then
      raise exception 'INVALID_KIND';
    end if;

    publish_state:=coalesce(p_is_published,false);

    insert into public.news(
      title,body,kind,is_published,published_at,created_by,created_by_name,created_at,updated_at
    )
    values(
      trim(p_title),trim(p_body),kind,publish_state,
      case when publish_state then now() else null end,
      actor_id,actor_name,now(),now()
    )
    returning * into created;

    insert into public.audit_logs(
      actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
    )
    values(
      actor_id,actor_tg_id,
      case when publish_state then 'NEWS_PUBLISH' else 'NEWS_CREATE' end,
      'news',created.id,null,
      jsonb_build_object(
        'title',created.title,'kind',created.kind,
        'is_published',created.is_published,
        'published_at',created.published_at
      )
    );

    return jsonb_build_object(
      'success',true,
      'action',action,
      'id',created.id,
      'title',created.title,
      'kind',created.kind,
      'is_published',created.is_published,
      'published_at',created.published_at
    );
  end if;

  if p_news_id is null then
    raise exception 'NEWS_NOT_FOUND';
  end if;

  select * into existing
  from public.news n
  where n.id=p_news_id
  for update;

  if not found then
    raise exception 'NEWS_NOT_FOUND';
  end if;

  if action='ARCHIVE' then
    update public.news
    set is_published=false,
        published_at=null,
        updated_at=now()
    where id=p_news_id
    returning * into created;
  else
    if p_title is not null and char_length(trim(p_title)) not between 2 and 200 then
      raise exception 'INVALID_TITLE';
    end if;
    if p_body is not null and char_length(trim(p_body)) not between 2 and 10000 then
      raise exception 'INVALID_BODY';
    end if;
    if p_kind is not null and clean_kind not in ('NEWS','UPDATE') then
      raise exception 'INVALID_KIND';
    end if;

    update public.news
    set title=coalesce(nullif(trim(p_title),''),title),
        body=coalesce(nullif(trim(p_body),''),body),
        kind=coalesce(nullif(kind,''),news.kind),
        is_published=coalesce(p_is_published,news.is_published),
        published_at=case
          when p_is_published=true and not news.is_published then now()
          when p_is_published=false then null
          else news.published_at
        end,
        updated_at=now()
    where id=p_news_id
    returning * into created;
  end if;

  insert into public.audit_logs(
    actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data
  )
  values(
    actor_id,actor_tg_id,
    case
      when action='ARCHIVE' then 'NEWS_ARCHIVE'
      when p_is_published=true and not existing.is_published then 'NEWS_PUBLISH'
      else 'NEWS_UPDATE'
    end,
    'news',created.id,
    jsonb_build_object(
      'title',existing.title,'kind',existing.kind,
      'is_published',existing.is_published,
      'published_at',existing.published_at
    ),
    jsonb_build_object(
      'title',created.title,'kind',created.kind,
      'is_published',created.is_published,
      'published_at',created.published_at
    )
  );

  return jsonb_build_object(
    'success',true,
    'action',action,
    'id',created.id,
    'title',created.title,
    'kind',created.kind,
    'is_published',created.is_published,
    'published_at',created.published_at
  );
end;
$function$;

revoke all on function public.staff_manage_news(text,uuid,text,text,text,boolean) from public,anon;
grant execute on function public.staff_manage_news(text,uuid,text,text,text,boolean) to authenticated;
