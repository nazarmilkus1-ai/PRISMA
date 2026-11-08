-- Harden PRISMA market lifecycle: expired listings, inquiry state transitions and closure fan-out.

create or replace function private.prisma_participant_create_market_inquiry(
  p_user_id uuid,p_listing_id uuid,p_message text
) returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  listing record;
  inquiry_id uuid;
  clean_message text:=trim(coalesce(p_message,''));
  requester_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_message) not between 3 and 1000 then raise exception 'INVALID_INQUIRY'; end if;

  select m.id,m.seller_id,m.title,m.status,m.expires_at into listing
  from public.market_listings m where m.id=p_listing_id for update;

  if listing.id is null
     or listing.status<>'ACTIVE'
     or (listing.expires_at is not null and listing.expires_at<=now()) then
    raise exception 'LISTING_NOT_FOUND';
  end if;
  if listing.seller_id=p_user_id then raise exception 'SELF_LISTING_FORBIDDEN'; end if;
  if exists(
    select 1 from public.market_inquiries i
    where i.listing_id=p_listing_id and i.requester_id=p_user_id and i.status<>'CLOSED'
  ) then raise exception 'INQUIRY_ALREADY_OPEN'; end if;

  insert into public.market_inquiries(listing_id,requester_id,seller_id,message)
  values(p_listing_id,p_user_id,listing.seller_id,clean_message)
  returning id into inquiry_id;

  select u.minecraft_nickname into requester_nick from public.users u where u.id=p_user_id;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select listing.seller_id,u.telegram_id,'telegram','MARKET','Новый запрос в рынке',
    coalesce(requester_nick,'Участник')||' отправил запрос по объявлению «'||listing.title||'».',
    jsonb_build_object('inquiry_id',inquiry_id,'listing_id',listing.id,'source','participant_site')
  from public.users u
  where u.id=listing.seller_id and u.telegram_id is not null;

  return jsonb_build_object('success',true,'inquiry_id',inquiry_id);
end;
$function$;

create or replace function private.prisma_participant_respond_market_inquiry(
  p_user_id uuid,p_inquiry_id uuid,p_response text
) returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  inquiry record;
  clean_response text:=trim(coalesce(p_response,''));
  seller_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_response) not between 3 and 1500 then raise exception 'INVALID_INQUIRY_RESPONSE'; end if;

  select i.id,i.requester_id,i.seller_id,i.status,m.title,i.listing_id,m.status listing_status,m.expires_at
  into inquiry
  from public.market_inquiries i
  join public.market_listings m on m.id=i.listing_id
  where i.id=p_inquiry_id
  for update;

  if inquiry.id is null then raise exception 'INQUIRY_NOT_FOUND'; end if;
  if inquiry.seller_id<>p_user_id then raise exception 'INQUIRY_FORBIDDEN'; end if;
  if inquiry.status<>'OPEN' then
    if inquiry.status='CLOSED' then raise exception 'INQUIRY_CLOSED'; end if;
    raise exception 'INQUIRY_ALREADY_ANSWERED';
  end if;
  if inquiry.listing_status<>'ACTIVE'
     or (inquiry.expires_at is not null and inquiry.expires_at<=now()) then
    update public.market_inquiries
    set status='CLOSED',closed_at=now(),updated_at=now()
    where id=p_inquiry_id and status<>'CLOSED';
    raise exception 'INQUIRY_CLOSED';
  end if;

  update public.market_inquiries
  set response=clean_response,status='ANSWERED',responded_at=now(),updated_at=now()
  where id=p_inquiry_id and status='OPEN';

  select u.minecraft_nickname into seller_nick from public.users u where u.id=p_user_id;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select inquiry.requester_id,u.telegram_id,'telegram','MARKET','Ответ по запросу',
    coalesce(seller_nick,'Продавец')||' ответил на ваш запрос по объявлению «'||inquiry.title||'». Откройте рынок, чтобы прочитать ответ.',
    jsonb_build_object('inquiry_id',inquiry.id,'listing_id',inquiry.listing_id,'source','participant_site')
  from public.users u
  where u.id=inquiry.requester_id and u.telegram_id is not null;

  return jsonb_build_object('success',true,'inquiry_id',p_inquiry_id,'status','ANSWERED');
end;
$function$;

create or replace function private.prisma_participant_close_market_listing(
  p_user_id uuid,p_listing_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  listing record;
  closed_count integer:=0;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select m.id,m.title into listing
  from public.market_listings m
  where m.id=p_listing_id and m.seller_id=p_user_id and m.status='ACTIVE'
  for update;

  if listing.id is null then raise exception 'LISTING_NOT_FOUND'; end if;

  update public.market_listings
  set status='CLOSED',updated_at=now()
  where id=p_listing_id and status='ACTIVE';

  with closed as (
    update public.market_inquiries
    set status='CLOSED',closed_at=now(),updated_at=now()
    where listing_id=p_listing_id and status<>'CLOSED'
    returning id,requester_id
  )
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select c.requester_id,u.telegram_id,'telegram','MARKET','Объявление снято',
    'Владелец снял объявление «'||listing.title||'». Открытые запросы по нему закрыты.',
    jsonb_build_object('inquiry_id',c.id,'listing_id',p_listing_id,'source','participant_site')
  from closed c
  join public.users u on u.id=c.requester_id
  where c.requester_id<>p_user_id and u.telegram_id is not null;

  get diagnostics closed_count = row_count;
  return jsonb_build_object('success',true,'listing_id',p_listing_id,'status','CLOSED','inquiries_closed',closed_count);
end;
$function$;

create or replace function public.participant_close_market_listing(p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid()) and u.deleted_at is null
  limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_close_market_listing(uid,p_listing_id);
end;
$function$;

revoke all on function public.participant_close_market_listing(uuid) from public,anon;
grant execute on function public.participant_close_market_listing(uuid) to authenticated;
