drop policy if exists market_inquiries_select on public.market_inquiries;

create policy market_inquiries_select on public.market_inquiries
for select to authenticated
using (
  exists(
    select 1 from public.users u
    where u.id=market_inquiries.requester_id
      and u.auth_user_id=(select auth.uid())
  )
  or exists(
    select 1 from public.users u
    where u.id=market_inquiries.seller_id
      and u.auth_user_id=(select auth.uid())
  )
);

create or replace function private.prisma_participant_respond_market_inquiry(
  p_user_id uuid,p_inquiry_id uuid,p_response text
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  inquiry record;
  clean_response text:=trim(coalesce(p_response,''));
  seller_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_response) not between 3 and 1500 then raise exception 'INVALID_INQUIRY_RESPONSE'; end if;

  select i.id,i.requester_id,i.seller_id,i.status,m.title,i.listing_id
  into inquiry
  from public.market_inquiries i
  join public.market_listings m on m.id=i.listing_id
  where i.id=p_inquiry_id
  for update;

  if inquiry.id is null then raise exception 'INQUIRY_NOT_FOUND'; end if;
  if inquiry.seller_id<>p_user_id then raise exception 'INQUIRY_FORBIDDEN'; end if;
  if inquiry.status='CLOSED' then raise exception 'INQUIRY_CLOSED'; end if;

  update public.market_inquiries
  set response=clean_response,status='ANSWERED',responded_at=now(),updated_at=now()
  where id=p_inquiry_id;

  select u.minecraft_nickname into seller_nick
  from public.users u where u.id=p_user_id;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select inquiry.requester_id,u.telegram_id,'telegram','MARKET','Ответ по запросу',
    coalesce(seller_nick,'Продавец')||' ответил на ваш запрос по объявлению «'||inquiry.title||'». Откройте рынок, чтобы прочитать ответ.',
    jsonb_build_object('inquiry_id',inquiry.id,'listing_id',inquiry.listing_id,'source','participant_site')
  from public.users u where u.id=inquiry.requester_id and u.telegram_id is not null;

  return jsonb_build_object('success',true,'inquiry_id',p_inquiry_id,'status','ANSWERED');
end;
$function$;

create or replace function private.prisma_participant_close_market_inquiry(
  p_user_id uuid,p_inquiry_id uuid
)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  inquiry record;
  closed_partner uuid;
  actor_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select i.id,i.requester_id,i.seller_id,i.status,i.listing_id,m.title
  into inquiry
  from public.market_inquiries i
  join public.market_listings m on m.id=i.listing_id
  where i.id=p_inquiry_id
  for update;

  if inquiry.id is null or inquiry.status='CLOSED' then raise exception 'INQUIRY_NOT_FOUND'; end if;
  if inquiry.requester_id<>p_user_id and inquiry.seller_id<>p_user_id then raise exception 'INQUIRY_NOT_FOUND'; end if;

  closed_partner:=case when inquiry.requester_id=p_user_id then inquiry.seller_id else inquiry.requester_id end;

  update public.market_inquiries
  set status='CLOSED',closed_at=now(),updated_at=now()
  where id=p_inquiry_id;

  select u.minecraft_nickname into actor_nick
  from public.users u where u.id=p_user_id;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select closed_partner,u.telegram_id,'telegram','MARKET','Запрос закрыт',
    coalesce(actor_nick,'Участник')||' закрыл запрос по объявлению «'||inquiry.title||'».',
    jsonb_build_object('inquiry_id',inquiry.id,'listing_id',inquiry.listing_id,'source','participant_site')
  from public.users u where u.id=closed_partner and u.telegram_id is not null;

  return jsonb_build_object('success',true,'inquiry_id',p_inquiry_id,'status','CLOSED');
end;
$function$;