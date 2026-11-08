-- PRISMA staff market moderation contracts.

insert into public.permissions(key,description,category)
values
  ('market.view','Просмотр рынка и запросов','market'),
  ('market.manage','Модерация рынка и запросов','market')
on conflict (key) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.key in ('market.view','market.manage')
where r.name in ('owner','head_admin','admin','moderator')
on conflict do nothing;

create or replace function public.staff_get_market(
  p_query text default '',
  p_status text default null,
  p_limit integer default 100
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
  q text := trim(coalesce(p_query,''));
  status_filter text := upper(trim(coalesce(p_status,'')));
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id and p.key='market.view'
  ) then raise exception 'PERMISSION_DENIED'; end if;

  if length(q)>64 then q:=left(q,64); end if;
  if status_filter not in ('ACTIVE','CLOSED','EXPIRED') then status_filter:=''; end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        m.id,
        m.seller_id,
        m.kind,
        m.title,
        m.description,
        m.price_text,
        m.terms,
        m.status,
        case
          when m.status='ACTIVE' and m.expires_at is not null and m.expires_at<=now() then 'EXPIRED'
          else m.status
        end as effective_status,
        m.created_at,
        m.updated_at,
        m.expires_at,
        u.minecraft_nickname,
        u.telegram_username,
        coalesce(i.open_count,0)::integer as open_inquiries,
        coalesce(i.total_count,0)::integer as total_inquiries
      from public.market_listings m
      join public.users u on u.id=m.seller_id
      left join lateral (
        select
          count(*) filter (where mi.status<>'CLOSED') as open_count,
          count(*) as total_count
        from public.market_inquiries mi
        where mi.listing_id=m.id
      ) i on true
      where u.deleted_at is null
        and (
          status_filter=''
          or case
               when m.status='ACTIVE' and m.expires_at is not null and m.expires_at<=now() then 'EXPIRED'
               else m.status
             end = status_filter
        )
        and (
          q=''
          or m.title ilike '%'||q||'%'
          or coalesce(m.description,'') ilike '%'||q||'%'
          or coalesce(m.price_text,'') ilike '%'||q||'%'
          or coalesce(u.minecraft_nickname,'') ilike '%'||q||'%'
        )
      order by m.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),300))
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.staff_get_market_inquiries(
  p_listing_id uuid,
  p_limit integer default 50
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor_id uuid;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.id into actor_id
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
  limit 1;

  if actor_id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor_id and p.key='market.view'
  ) then raise exception 'PERMISSION_DENIED'; end if;

  if not exists(select 1 from public.market_listings m where m.id=p_listing_id) then
    raise exception 'LISTING_NOT_FOUND';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        i.id,
        i.listing_id,
        i.requester_id,
        i.seller_id,
        i.message,
        i.response,
        i.status,
        i.created_at,
        i.updated_at,
        i.responded_at,
        i.closed_at,
        requester.minecraft_nickname as requester_nickname,
        seller.minecraft_nickname as seller_nickname,
        m.title as listing_title
      from public.market_inquiries i
      join public.market_listings m on m.id=i.listing_id
      join public.users requester on requester.id=i.requester_id
      join public.users seller on seller.id=i.seller_id
      where i.listing_id=p_listing_id
      order by i.created_at desc
      limit greatest(1,least(coalesce(p_limit,50),100))
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.staff_manage_market(
  p_action text,
  p_listing_id uuid default null,
  p_inquiry_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  actor_uid uuid := (select auth.uid());
  actor public.users%rowtype;
  listing public.market_listings%rowtype;
  inquiry public.market_inquiries%rowtype;
  changed integer := 0;
begin
  if actor_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into actor
  from public.users u
  where u.auth_user_id=actor_uid and u.deleted_at is null
  limit 1;

  if actor.id is null then raise exception 'ACTOR_NOT_FOUND'; end if;
  if not exists(
    select 1
    from public.admins a
    join public.role_permissions rp on rp.role_id=a.role_id
    join public.permissions p on p.id=rp.permission_id
    where a.user_id=actor.id and p.key='market.manage'
  ) then raise exception 'PERMISSION_DENIED'; end if;

  case upper(trim(coalesce(p_action,'')))
    when 'CLOSE_LISTING' then
      if p_listing_id is null then raise exception 'LISTING_REQUIRED'; end if;

      select * into listing
      from public.market_listings
      where id=p_listing_id
      for update;

      if listing.id is null then raise exception 'LISTING_NOT_FOUND'; end if;
      if listing.status<>'ACTIVE' then raise exception 'LISTING_NOT_ACTIVE'; end if;

      update public.market_listings
      set status='CLOSED',updated_at=now()
      where id=p_listing_id and status='ACTIVE';

      with closed as (
        update public.market_inquiries
        set status='CLOSED',closed_at=now(),updated_at=now()
        where listing_id=p_listing_id and status<>'CLOSED'
        returning id,requester_id,seller_id
      ),
      recipients as (
        select requester_id as user_id,id as inquiry_id from closed
        union
        select seller_id as user_id,id as inquiry_id from closed
      )
      insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
      select r.user_id,u.telegram_id,'telegram','MARKET','Объявление снято администрацией',
        'Администрация сняла объявление «'||listing.title||'». Связанные запросы закрыты.',
        jsonb_build_object('inquiry_id',r.inquiry_id,'listing_id',p_listing_id,'source','staff_market')
      from recipients r
      join public.users u on u.id=r.user_id
      where r.user_id<>actor.id and u.telegram_id is not null;

      insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
      values(
        actor.id,actor.telegram_id,'market.listing_close','market_listing',listing.id,
        jsonb_build_object('status',listing.status),
        jsonb_build_object('status','CLOSED')
      );

      return jsonb_build_object('success',true,'action','CLOSE_LISTING','listing_id',p_listing_id);

    when 'CLOSE_INQUIRY' then
      if p_inquiry_id is null then raise exception 'INQUIRY_REQUIRED'; end if;

      select i.* into inquiry
      from public.market_inquiries i
      where i.id=p_inquiry_id
      for update;

      if inquiry.id is null then raise exception 'INQUIRY_NOT_FOUND'; end if;
      if inquiry.status='CLOSED' then raise exception 'INQUIRY_CLOSED'; end if;

      update public.market_inquiries
      set status='CLOSED',closed_at=now(),updated_at=now()
      where id=p_inquiry_id and status<>'CLOSED';

      get diagnostics changed=row_count;

      insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
      select u.id,u.telegram_id,'telegram','MARKET','Запрос закрыт администрацией',
        'Администрация закрыла запрос по объявлению.',
        jsonb_build_object('inquiry_id',inquiry.id,'listing_id',inquiry.listing_id,'source','staff_market')
      from public.users u
      where u.id in (inquiry.requester_id,inquiry.seller_id)
        and u.id<>actor.id
        and u.telegram_id is not null;

      insert into public.audit_logs(actor_user_id,actor_tg_id,action,target_type,target_id,old_data,new_data)
      values(
        actor.id,actor.telegram_id,'market.inquiry_close','market_inquiry',inquiry.id,
        jsonb_build_object('previous_status',inquiry.status),
        jsonb_build_object('status','CLOSED')
      );

      return jsonb_build_object('success',true,'action','CLOSE_INQUIRY','inquiry_id',p_inquiry_id,'changed',changed);

    else
      raise exception 'UNKNOWN_ACTION';
  end case;
end;
$function$;

revoke all on function public.staff_get_market(text,text,integer) from public,anon;
revoke all on function public.staff_get_market_inquiries(uuid,integer) from public,anon;
revoke all on function public.staff_manage_market(text,uuid,uuid) from public,anon;
grant execute on function public.staff_get_market(text,text,integer) to authenticated;
grant execute on function public.staff_get_market_inquiries(uuid,integer) to authenticated;
grant execute on function public.staff_manage_market(text,uuid,uuid) to authenticated;