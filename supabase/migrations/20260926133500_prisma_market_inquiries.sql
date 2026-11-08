create table if not exists public.market_inquiries(
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  requester_id uuid not null references public.users(id) on delete cascade,
  seller_id uuid not null references public.users(id) on delete cascade,
  message text not null,
  response text,
  status text not null default 'OPEN' check(status in('OPEN','ANSWERED','CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  closed_at timestamptz,
  constraint market_inquiries_not_self check(requester_id<>seller_id)
);

create index if not exists market_inquiries_requester_idx on public.market_inquiries(requester_id,status,created_at desc);
create index if not exists market_inquiries_seller_idx on public.market_inquiries(seller_id,status,created_at desc);
create index if not exists market_inquiries_listing_idx on public.market_inquiries(listing_id,created_at desc);
create unique index if not exists market_inquiries_active_unique on public.market_inquiries(listing_id,requester_id) where status<>'CLOSED';

alter table public.market_inquiries enable row level security;
drop policy if exists market_inquiries_select on public.market_inquiries;
create policy market_inquiries_select on public.market_inquiries for select to authenticated
using (requester_id=(select auth.uid()) or seller_id=(select auth.uid()));
revoke all on public.market_inquiries from anon,authenticated;

alter table public.notification_preferences add column if not exists market boolean not null default true;
update public.notification_preferences set market=true where market is null;

create or replace function private.prisma_participant_create_market_inquiry(p_user_id uuid,p_listing_id uuid,p_message text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare listing record; inquiry_id uuid; clean_message text:=trim(coalesce(p_message,'')); requester_nick text;
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_message) not between 3 and 1000 then raise exception 'INVALID_INQUIRY'; end if;
  select m.id,m.seller_id,m.title,m.status into listing
  from public.market_listings m where m.id=p_listing_id for update;
  if listing.id is null or listing.status<>'ACTIVE' then raise exception 'LISTING_NOT_FOUND'; end if;
  if listing.seller_id=p_user_id then raise exception 'SELF_LISTING_FORBIDDEN'; end if;
  if exists(select 1 from public.market_inquiries i where i.listing_id=p_listing_id and i.requester_id=p_user_id and i.status<>'CLOSED') then raise exception 'INQUIRY_ALREADY_OPEN'; end if;
  insert into public.market_inquiries(listing_id,requester_id,seller_id,message) values(p_listing_id,p_user_id,listing.seller_id,clean_message) returning id into inquiry_id;
  select u.minecraft_nickname into requester_nick from public.users u where u.id=p_user_id;
  insert into public.notifications(user_id,telegram_id,channel,kind,title,body,data)
  select listing.seller_id,u.telegram_id,'telegram','MARKET','Новый запрос в рынке',
    coalesce(requester_nick,'Участник')||' отправил запрос по объявлению «'||listing.title||'».',
    jsonb_build_object('inquiry_id',inquiry_id,'listing_id',listing.id,'source','participant_site')
  from public.users u where u.id=listing.seller_id and u.telegram_id is not null;
  return jsonb_build_object('success',true,'inquiry_id',inquiry_id);
end;
$function$;

create or replace function private.prisma_participant_respond_market_inquiry(p_user_id uuid,p_inquiry_id uuid,p_response text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare inquiry record; clean_response text:=trim(coalesce(p_response,''));
begin
  perform private.prisma_participant_require_access(p_user_id);
  if char_length(clean_response) not between 3 and 1500 then raise exception 'INVALID_INQUIRY_RESPONSE'; end if;
  select i.id,i.requester_id,i.seller_id,i.status,m.title into inquiry
  from public.market_inquiries i join public.market_listings m on m.id=i.listing_id
  where i.id=p_inquiry_id for update;
  if inquiry.id is null then raise exception 'INQUIRY_NOT_FOUND'; end if;
  if inquiry.seller_id<>p_user_id then raise exception 'INQUIRY_FORBIDDEN'; end if;
  if inquiry.status='CLOSED' then raise exception 'INQUIRY_CLOSED'; end if;
  update public.market_inquiries set response=clean_response,status='ANSWERED',responded_at=now(),updated_at=now() where id=p_inquiry_id;
  return jsonb_build_object('success',true,'inquiry_id',p_inquiry_id,'status','ANSWERED');
end;
$function$;

create or replace function private.prisma_participant_close_market_inquiry(p_user_id uuid,p_inquiry_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare changed uuid;
begin
  perform private.prisma_participant_require_access(p_user_id);
  update public.market_inquiries set status='CLOSED',closed_at=now(),updated_at=now()
  where id=p_inquiry_id and status<>'CLOSED' and (requester_id=p_user_id or seller_id=p_user_id)
  returning id into changed;
  if changed is null then raise exception 'INQUIRY_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'inquiry_id',changed,'status','CLOSED');
end;
$function$;

create or replace function private.prisma_participant_get_market_inquiries(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select i.id,i.listing_id,i.requester_id,i.seller_id,i.message,i.response,i.status,i.created_at,i.updated_at,i.responded_at,i.closed_at,
             m.title listing_title,m.kind listing_kind,
             case when i.requester_id=p_user_id then seller.minecraft_nickname else requester.minecraft_nickname end partner_nickname,
             (i.seller_id=p_user_id) incoming
      from public.market_inquiries i
      join public.market_listings m on m.id=i.listing_id
      join public.users requester on requester.id=i.requester_id
      join public.users seller on seller.id=i.seller_id
      where i.requester_id=p_user_id or i.seller_id=p_user_id
      order by i.created_at desc limit 50
    ) x
  ),'[]'::jsonb);
end;
$function$;

create or replace function public.participant_create_market_inquiry(p_listing_id uuid,p_message text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_create_market_inquiry(uid,p_listing_id,p_message);
end; $function$;

create or replace function public.participant_respond_market_inquiry(p_inquiry_id uuid,p_response text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_respond_market_inquiry(uid,p_inquiry_id,p_response);
end; $function$;

create or replace function public.participant_close_market_inquiry(p_inquiry_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_close_market_inquiry(uid,p_inquiry_id);
end; $function$;

create or replace function public.participant_get_market_inquiries()
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare uid uuid; begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_get_market_inquiries(uid);
end; $function$;

revoke all on function public.participant_create_market_inquiry(uuid,text) from public,anon;
revoke all on function public.participant_respond_market_inquiry(uuid,text) from public,anon;
revoke all on function public.participant_close_market_inquiry(uuid) from public,anon;
revoke all on function public.participant_get_market_inquiries() from public,anon;
grant execute on function public.participant_create_market_inquiry(uuid,text) to authenticated;
grant execute on function public.participant_respond_market_inquiry(uuid,text) to authenticated;
grant execute on function public.participant_close_market_inquiry(uuid) to authenticated;
grant execute on function public.participant_get_market_inquiries() to authenticated;