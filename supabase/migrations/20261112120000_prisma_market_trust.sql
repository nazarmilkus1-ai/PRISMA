-- Market trust: reviews after an accepted offer + read RPCs for reputation and anti-fraud signals.
create table if not exists public.market_reviews(
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.market_offers(id) on delete cascade,
  reviewer_id uuid not null references public.users(id) on delete cascade,
  reviewee_id uuid not null references public.users(id) on delete cascade,
  rating smallint not null check(rating between 1 and 5),
  comment text check(comment is null or char_length(comment)<=300),
  created_at timestamptz not null default now(),
  constraint market_reviews_not_self check(reviewer_id<>reviewee_id),
  constraint market_reviews_once unique(offer_id,reviewer_id)
);
create index if not exists market_reviews_reviewee_idx on public.market_reviews(reviewee_id,created_at desc);
alter table public.market_reviews enable row level security;
revoke all on public.market_reviews from anon,authenticated;

-- Only the two parties of an ACCEPTED offer may review each other, once, within 60 days.
create or replace function public.bot_create_market_review(p_tg_id bigint,p_offer_id uuid,p_rating int,p_comment text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; o record; other uuid; txt text:=nullif(btrim(coalesce(p_comment,'')),'');
begin
  select id into uid from public.users where telegram_id=p_tg_id and deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'REVIEW_RATING_INVALID'; end if;
  if txt is not null and char_length(txt)>300 then raise exception 'REVIEW_TEXT_TOO_LONG'; end if;
  select * into o from public.market_offers where id=p_offer_id;
  if not found or o.status<>'ACCEPTED' then raise exception 'REVIEW_OFFER_NOT_ACCEPTED'; end if;
  if uid not in (o.buyer_id,o.seller_id) then raise exception 'REVIEW_NOT_A_PARTY'; end if;
  if coalesce(o.responded_at,o.created_at) < now()-interval '60 days' then raise exception 'REVIEW_WINDOW_CLOSED'; end if;
  other:=case when uid=o.buyer_id then o.seller_id else o.buyer_id end;
  begin
    insert into public.market_reviews(offer_id,reviewer_id,reviewee_id,rating,comment) values(p_offer_id,uid,other,p_rating,txt);
  exception when unique_violation then raise exception 'REVIEW_ALREADY_LEFT';
  end;
  return jsonb_build_object('ok',true);
end; $function$;

-- Accepted offers of this user that they have not reviewed yet.
create or replace function public.bot_my_reviewable_offers(p_tg_id bigint)
returns jsonb language sql security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('offer_id',o.id,'listing_title',l.title,'partner_nickname',pn.minecraft_nickname,
           'price_text',o.price_text) order by o.responded_at desc),'[]'::jsonb)
  from public.users me
  join public.market_offers o on o.status='ACCEPTED' and me.id in (o.buyer_id,o.seller_id)
       and coalesce(o.responded_at,o.created_at)>=now()-interval '60 days'
  join public.market_listings l on l.id=o.listing_id
  join public.users pn on pn.id=case when me.id=o.buyer_id then o.seller_id else o.buyer_id end
  where me.telegram_id=p_tg_id and me.deleted_at is null
    and not exists(select 1 from public.market_reviews r where r.offer_id=o.id and r.reviewer_id=me.id);
$function$;

-- Reputation by Minecraft nickname: count, average and the 3 latest comments.
create or replace function public.bot_market_reputation(p_nick text)
returns jsonb language sql security definer set search_path to ''
as $function$
  select jsonb_build_object(
    'nickname',u.minecraft_nickname,
    'reviews',count(r.id),
    'average',round(avg(r.rating)::numeric,2),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('rating',x.rating,'comment',x.comment,'at',x.created_at))
                        from (select rating,comment,created_at from public.market_reviews
                               where reviewee_id=u.id order by created_at desc limit 3) x),'[]'::jsonb))
  from public.users u left join public.market_reviews r on r.reviewee_id=u.id
  where lower(u.minecraft_nickname)=lower(btrim(coalesce(p_nick,''))) and u.deleted_at is null
  group by u.id;
$function$;

-- Staff signal input: recent listings with seller age, activity and reputation. Scoring happens in the bot.
create or replace function public.bot_market_risk_data(p_hours int default 72)
returns jsonb language sql security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',l.id,'kind',l.kind,'title',l.title,'description',l.description,'terms',l.terms,'price_text',l.price_text,
    'created_at',l.created_at,'seller_id',l.seller_id,'seller_nickname',u.minecraft_nickname,'seller_telegram_id',u.telegram_id,
    'seller_created_at',u.created_at,
    'seller_listings_24h',(select count(*) from public.market_listings x where x.seller_id=l.seller_id and x.created_at>now()-interval '24 hours'),
    'seller_reviews',(select count(*) from public.market_reviews r where r.reviewee_id=l.seller_id),
    'seller_avg_rating',(select round(avg(r.rating)::numeric,2) from public.market_reviews r where r.reviewee_id=l.seller_id),
    'seller_low_reviews',(select count(*) from public.market_reviews r where r.reviewee_id=l.seller_id and r.rating<=2)
  ) order by l.created_at desc),'[]'::jsonb)
  from public.market_listings l join public.users u on u.id=l.seller_id
  where l.status in ('ACTIVE','RESERVED') and l.created_at>now()-make_interval(hours=>greatest(1,least(coalesce(p_hours,72),720)));
$function$;

revoke all on function public.bot_create_market_review(bigint,uuid,int,text) from public,anon,authenticated;
revoke all on function public.bot_my_reviewable_offers(bigint) from public,anon,authenticated;
revoke all on function public.bot_market_reputation(text) from public,anon,authenticated;
revoke all on function public.bot_market_risk_data(int) from public,anon,authenticated;
grant execute on function public.bot_create_market_review(bigint,uuid,int,text) to service_role;
grant execute on function public.bot_my_reviewable_offers(bigint) to service_role;
grant execute on function public.bot_market_reputation(text) to service_role;
grant execute on function public.bot_market_risk_data(int) to service_role;
