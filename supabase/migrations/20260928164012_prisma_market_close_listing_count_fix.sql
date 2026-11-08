-- PRISMA 2.0.0: return the number of inquiries actually closed when closing a listing.
create or replace function private.prisma_participant_close_market_listing(
  p_user_id uuid,
  p_listing_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
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
  ),
  notify as (
    insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
    select c.requester_id,u.telegram_id,'telegram','MARKET','Объявление снято',
      'Владелец снял объявление «'||listing.title||'». Открытые запросы по нему закрыты.',
      jsonb_build_object('inquiry_id',c.id,'listing_id',p_listing_id,'source','participant_site')
    from closed c
    join public.users u on u.id=c.requester_id
    where c.requester_id<>p_user_id and u.telegram_id is not null
    returning 1
  ),
  stats as (
    select (select count(*) from closed)::integer as closed_count,
           (select count(*) from notify)::integer as notified_count
  )
  select stats.closed_count
  into closed_count
  from stats;

  return jsonb_build_object(
    'success',true,
    'listing_id',p_listing_id,
    'status','CLOSED',
    'inquiries_closed',closed_count
  );
end;
$function$;