drop function if exists public.participant_update_market_listing(uuid,text,text,text,text,text);
drop function if exists private.prisma_participant_update_market_listing(uuid,uuid,text,text,text,text,text);

create or replace function private.prisma_participant_create_market_listing(
  p_user_id uuid,
  p_kind text,
  p_title text,
  p_description text default null,
  p_price_text text default null,
  p_terms text default null,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_kind text := upper(trim(coalesce(p_kind,'')));
  v_title text := trim(coalesce(p_title,''));
  v_description text := trim(coalesce(p_description,''));
  v_price text := trim(coalesce(p_price_text,''));
  v_terms text := trim(coalesce(p_terms,''));
  v_listing_id uuid;
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

  insert into public.market_listings(
    seller_id,kind,title,description,price_text,terms,status,expires_at
  ) values (
    p_user_id,v_kind,v_title,
    nullif(v_description,''),
    nullif(v_price,''),
    nullif(v_terms,''),
    'ACTIVE',
    p_expires_at
  )
  returning id into v_listing_id;

  return jsonb_build_object(
    'success',true,
    'listing_id',v_listing_id,
    'status','ACTIVE',
    'expires_at',p_expires_at
  );
end;
$function$;

create or replace function public.participant_create_market_listing(
  p_kind text,
  p_title text,
  p_description text default null,
  p_price_text text default null,
  p_terms text default null,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
begin
  select u.id into uid
  from public.users u
  where u.auth_user_id=(select auth.uid())
    and u.deleted_at is null
  limit 1;

  if uid is null then
    raise exception 'USER_NOT_LINKED';
  end if;

  return private.prisma_participant_create_market_listing(
    uid,p_kind,p_title,p_description,p_price_text,p_terms,p_expires_at
  );
end;
$function$;

revoke execute on function public.participant_create_market_listing(text,text,text,text,text,timestamptz) from public,anon;
grant execute on function public.participant_create_market_listing(text,text,text,text,text,timestamptz) to authenticated;
