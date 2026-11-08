-- PRISMA v2: reconcile repository source with the live market update contract.
-- Remove legacy overloads created by 20260926123843 so a fresh migration replay
-- cannot leave an ambiguous/obsolete market update RPC behind.
drop function if exists private.prisma_participant_update_market_listing(uuid,uuid,text,text,text,text,text);
drop function if exists public.participant_update_market_listing(uuid,text,text,text,text,text);

-- Participant site already sends p_expires_at; keep the domain primitive authoritative.
-- Telegram receives the same domain capability through a service-role-only bridge.

create or replace function private.prisma_participant_update_market_listing(
  p_user_id uuid,
  p_listing_id uuid,
  p_kind text,
  p_title text,
  p_description text,
  p_price_text text,
  p_terms text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kind text := upper(trim(coalesce(p_kind,'')));
  v_title text := trim(coalesce(p_title,''));
  v_description text := trim(coalesce(p_description,''));
  v_price text := trim(coalesce(p_price_text,''));
  v_terms text := trim(coalesce(p_terms,''));
begin
  perform private.prisma_participant_require_access(p_user_id);

  if v_kind not in ('SELL','BUY','TRADE','SERVICE','OTHER')
     or char_length(v_title) < 3
     or char_length(v_title) > 100
     or char_length(v_description) > 1000
     or char_length(v_price) > 200
     or char_length(v_terms) > 500
     or (p_expires_at is not null and p_expires_at <= now()) then
    raise exception 'INVALID_LISTING';
  end if;

  update public.market_listings
  set
    kind=v_kind,
    title=v_title,
    description=nullif(v_description,''),
    price_text=nullif(v_price,''),
    terms=nullif(v_terms,''),
    expires_at=p_expires_at,
    updated_at=now()
  where id=p_listing_id
    and seller_id=p_user_id
    and status='ACTIVE';

  if not found then
    raise exception 'LISTING_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'success',true,
    'listing_id',p_listing_id,
    'status','ACTIVE',
    'expires_at',p_expires_at
  );
end;
$function$;

create or replace function public.participant_update_market_listing(
  p_listing_id uuid,
  p_kind text,
  p_title text,
  p_description text default null,
  p_price_text text default null,
  p_terms text default null,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_LINKED'; end if;

  return private.prisma_participant_update_market_listing(
    uid,p_listing_id,p_kind,p_title,p_description,p_price_text,p_terms,p_expires_at
  );
end;
$function$;

revoke all on function public.participant_update_market_listing(uuid,text,text,text,text,text,timestamptz)
from public,anon;
grant execute on function public.participant_update_market_listing(uuid,text,text,text,text,text,timestamptz)
to authenticated;

create or replace function public.bot_update_market_listing(
  p_tg_id bigint,
  p_listing_id uuid,
  p_kind text,
  p_title text,
  p_description text default null,
  p_price_text text default null,
  p_terms text default null,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.telegram_id=p_tg_id
    and u.deleted_at is null
  limit 1;

  if uid is null then raise exception 'USER_NOT_FOUND'; end if;

  return private.prisma_participant_update_market_listing(
    uid,p_listing_id,p_kind,p_title,p_description,p_price_text,p_terms,p_expires_at
  );
end;
$function$;

revoke all on function public.bot_update_market_listing(bigint,uuid,text,text,text,text,text,timestamptz)
from public,anon,authenticated;
grant execute on function public.bot_update_market_listing(bigint,uuid,text,text,text,text,text,timestamptz)
to service_role;
