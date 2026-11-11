-- Market bargaining: price offers with accept / reject / counter between buyer and seller.
-- One live (PENDING or ACCEPTED) offer per listing+buyer thread, at most 6 rounds, 72h to answer.

create table if not exists public.market_offers(
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  buyer_id uuid not null references public.users(id) on delete cascade,
  seller_id uuid not null references public.users(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  parent_offer_id uuid references public.market_offers(id) on delete set null,
  price_text text not null check(char_length(price_text) between 1 and 60),
  note text check(note is null or char_length(note)<=300),
  status text not null default 'PENDING' check(status in('PENDING','ACCEPTED','REJECTED','COUNTERED','WITHDRAWN')),
  round integer not null default 1 check(round between 1 and 6),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  expires_at timestamptz not null default now()+interval '72 hours',
  constraint market_offers_not_self check(buyer_id<>seller_id),
  constraint market_offers_author_party check(author_id in(buyer_id,seller_id))
);

create index if not exists market_offers_buyer_idx on public.market_offers(buyer_id,status,created_at desc);
create index if not exists market_offers_seller_idx on public.market_offers(seller_id,status,created_at desc);
create index if not exists market_offers_listing_idx on public.market_offers(listing_id,created_at desc);
create unique index if not exists market_offers_live_unique on public.market_offers(listing_id,buyer_id) where status in('PENDING','ACCEPTED');

alter table public.market_offers enable row level security;
drop policy if exists market_offers_select on public.market_offers;
create policy market_offers_select on public.market_offers for select to authenticated
using (
  exists(select 1 from public.users u where u.id=market_offers.buyer_id and u.auth_user_id=(select auth.uid()))
  or exists(select 1 from public.users u where u.id=market_offers.seller_id and u.auth_user_id=(select auth.uid()))
);
revoke all on public.market_offers from anon,authenticated;

create or replace function private.prisma_participant_create_market_offer(p_user_id uuid,p_listing_id uuid,p_price text,p_note text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  listing record;
  clean_price text:=trim(coalesce(p_price,''));
  clean_note text:=nullif(trim(coalesce(p_note,'')),'');
  offer_id uuid;
  buyer_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_price) not between 1 and 60 then raise exception 'INVALID_OFFER'; end if;
  if clean_note is not null and char_length(clean_note)>300 then raise exception 'INVALID_OFFER'; end if;

  select m.id,m.seller_id,m.title,m.status,m.expires_at into listing
  from public.market_listings m where m.id=p_listing_id for update;
  if listing.id is null or listing.status<>'ACTIVE' or (listing.expires_at is not null and listing.expires_at<=now()) then
    raise exception 'LISTING_NOT_FOUND';
  end if;
  if listing.seller_id=p_user_id then raise exception 'SELF_LISTING_FORBIDDEN'; end if;

  update public.market_offers set status='WITHDRAWN',responded_at=now()
  where listing_id=p_listing_id and buyer_id=p_user_id and status='PENDING' and expires_at<=now();
  if exists(select 1 from public.market_offers o where o.listing_id=p_listing_id and o.buyer_id=p_user_id and o.status in('PENDING','ACCEPTED')) then
    raise exception 'OFFER_ALREADY_OPEN';
  end if;

  insert into public.market_offers(listing_id,buyer_id,seller_id,author_id,price_text,note)
  values(p_listing_id,p_user_id,listing.seller_id,p_user_id,clean_price,clean_note)
  returning id into offer_id;

  select u.minecraft_nickname into buyer_nick from public.users u where u.id=p_user_id;
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select listing.seller_id,u.telegram_id,'telegram','MARKET','Новое предложение цены',
    coalesce(buyer_nick,'Участник')||' предлагает «'||clean_price||'» за «'||listing.title||'». Ответьте в течение 72 часов.',
    jsonb_build_object('offer_id',offer_id,'listing_id',p_listing_id,'source','market_offers')
  from public.users u where u.id=listing.seller_id and u.telegram_id is not null;

  return jsonb_build_object('success',true,'offer_id',offer_id);
end;
$function$;

create or replace function private.prisma_participant_respond_market_offer(p_user_id uuid,p_offer_id uuid,p_action text,p_price text,p_note text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare
  offer record;
  recipient uuid;
  action text:=lower(trim(coalesce(p_action,'')));
  clean_price text:=trim(coalesce(p_price,''));
  clean_note text:=nullif(trim(coalesce(p_note,'')),'');
  new_id uuid;
  actor_nick text;
  verb text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if action not in('accept','reject','counter') then raise exception 'INVALID_OFFER_ACTION'; end if;

  select o.id,o.listing_id,o.buyer_id,o.seller_id,o.author_id,o.status,o.round,o.expires_at,o.price_text,m.title,m.status listing_status
  into offer
  from public.market_offers o join public.market_listings m on m.id=o.listing_id
  where o.id=p_offer_id for update;
  if offer.id is null then raise exception 'OFFER_NOT_FOUND'; end if;

  recipient:=case when offer.author_id=offer.buyer_id then offer.seller_id else offer.buyer_id end;
  if recipient<>p_user_id then raise exception 'OFFER_FORBIDDEN'; end if;
  if offer.status<>'PENDING' then raise exception 'OFFER_CLOSED'; end if;
  if offer.expires_at<=now() then raise exception 'OFFER_EXPIRED'; end if;
  if offer.listing_status<>'ACTIVE' then raise exception 'LISTING_NOT_FOUND'; end if;

  select u.minecraft_nickname into actor_nick from public.users u where u.id=p_user_id;

  if action='counter' then
    if char_length(clean_price) not between 1 and 60 then raise exception 'INVALID_OFFER'; end if;
    if clean_note is not null and char_length(clean_note)>300 then raise exception 'INVALID_OFFER'; end if;
    if offer.round>=6 then raise exception 'OFFER_MAX_ROUNDS'; end if;
    update public.market_offers set status='COUNTERED',responded_at=now() where id=p_offer_id;
    insert into public.market_offers(listing_id,buyer_id,seller_id,author_id,parent_offer_id,price_text,note,round)
    values(offer.listing_id,offer.buyer_id,offer.seller_id,p_user_id,p_offer_id,clean_price,clean_note,offer.round+1)
    returning id into new_id;
    verb:=coalesce(actor_nick,'Участник')||' предлагает встречную цену «'||clean_price||'» за «'||offer.title||'».';
  elsif action='accept' then
    update public.market_offers set status='ACCEPTED',responded_at=now() where id=p_offer_id;
    verb:=coalesce(actor_nick,'Участник')||' принял(а) цену «'||offer.price_text||'» за «'||offer.title||'». Договоритесь о передаче в игре или в чате.';
  else
    update public.market_offers set status='REJECTED',responded_at=now() where id=p_offer_id;
    verb:=coalesce(actor_nick,'Участник')||' отклонил(а) цену «'||offer.price_text||'» за «'||offer.title||'».';
  end if;

  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select offer.author_id,u.telegram_id,'telegram','MARKET','Торг: ответ на предложение',verb,
    jsonb_build_object('offer_id',coalesce(new_id,p_offer_id),'listing_id',offer.listing_id,'source','market_offers')
  from public.users u where u.id=offer.author_id and u.telegram_id is not null;

  return jsonb_build_object('success',true,'offer_id',p_offer_id,'action',action,'counter_offer_id',new_id);
end;
$function$;

create or replace function private.prisma_participant_withdraw_market_offer(p_user_id uuid,p_offer_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare changed uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);
  update public.market_offers set status='WITHDRAWN',responded_at=now()
  where id=p_offer_id and author_id=p_user_id and status='PENDING'
  returning id into changed;
  if changed is null then raise exception 'OFFER_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'offer_id',changed,'status','WITHDRAWN');
end;
$function$;

create or replace function private.prisma_participant_get_market_offers(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select o.id,o.listing_id,o.price_text,o.note,o.status,o.round,o.created_at,o.responded_at,o.expires_at,
             m.title listing_title,
             case when o.buyer_id=p_user_id then seller.minecraft_nickname else buyer.minecraft_nickname end partner_nickname,
             (o.author_id=p_user_id) mine,
             (o.status='PENDING' and o.author_id<>p_user_id and o.expires_at>now() and m.status='ACTIVE') actionable,
             (o.status='PENDING' and o.expires_at<=now()) expired
      from public.market_offers o
      join public.market_listings m on m.id=o.listing_id
      join public.users buyer on buyer.id=o.buyer_id
      join public.users seller on seller.id=o.seller_id
      where o.buyer_id=p_user_id or o.seller_id=p_user_id
      order by o.created_at desc limit 50
    ) x
  ),'[]'::jsonb);
end;
$function$;

-- Bot (service_role) gateways
create or replace function public.bot_create_market_offer(p_tg_id bigint,p_listing_id uuid,p_price text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_create_market_offer(uid,p_listing_id,p_price,p_note);
end;
$function$;

create or replace function public.bot_respond_market_offer(p_tg_id bigint,p_offer_id uuid,p_action text,p_price text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_respond_market_offer(uid,p_offer_id,p_action,p_price,p_note);
end;
$function$;

create or replace function public.bot_withdraw_market_offer(p_tg_id bigint,p_offer_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_withdraw_market_offer(uid,p_offer_id);
end;
$function$;

create or replace function public.bot_get_market_offers(p_tg_id bigint)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_get_market_offers(uid);
end;
$function$;

-- Site (authenticated) gateways
create or replace function public.participant_create_market_offer(p_listing_id uuid,p_price text,p_note text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_create_market_offer(uid,p_listing_id,p_price,p_note);
end; $function$;

create or replace function public.participant_respond_market_offer(p_offer_id uuid,p_action text,p_price text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_respond_market_offer(uid,p_offer_id,p_action,p_price,p_note);
end; $function$;

create or replace function public.participant_withdraw_market_offer(p_offer_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_withdraw_market_offer(uid,p_offer_id);
end; $function$;

create or replace function public.participant_get_market_offers()
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_market_offers(uid);
end; $function$;

revoke all on function private.prisma_participant_create_market_offer(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function private.prisma_participant_respond_market_offer(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function private.prisma_participant_withdraw_market_offer(uuid,uuid) from public,anon,authenticated;
revoke all on function private.prisma_participant_get_market_offers(uuid) from public,anon,authenticated;

revoke all on function public.bot_create_market_offer(bigint,uuid,text,text) from public,anon,authenticated;
revoke all on function public.bot_respond_market_offer(bigint,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.bot_withdraw_market_offer(bigint,uuid) from public,anon,authenticated;
revoke all on function public.bot_get_market_offers(bigint) from public,anon,authenticated;
grant execute on function public.bot_create_market_offer(bigint,uuid,text,text) to service_role;
grant execute on function public.bot_respond_market_offer(bigint,uuid,text,text,text) to service_role;
grant execute on function public.bot_withdraw_market_offer(bigint,uuid) to service_role;
grant execute on function public.bot_get_market_offers(bigint) to service_role;

revoke all on function public.participant_create_market_offer(uuid,text,text) from public,anon;
revoke all on function public.participant_respond_market_offer(uuid,text,text,text) from public,anon;
revoke all on function public.participant_withdraw_market_offer(uuid) from public,anon;
revoke all on function public.participant_get_market_offers() from public,anon;
grant execute on function public.participant_create_market_offer(uuid,text,text) to authenticated;
grant execute on function public.participant_respond_market_offer(uuid,text,text,text) to authenticated;
grant execute on function public.participant_withdraw_market_offer(uuid) to authenticated;
grant execute on function public.participant_get_market_offers() to authenticated;
