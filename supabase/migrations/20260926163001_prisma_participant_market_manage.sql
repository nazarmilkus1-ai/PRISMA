-- Allow participants to safely close their own active market listings.

create or replace function private.prisma_participant_close_market_listing(p_user_id uuid,p_listing_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
begin
  perform private.prisma_participant_require_access(p_user_id);
  update public.market_listings
  set status='CLOSED',updated_at=now()
  where id=p_listing_id and seller_id=p_user_id and status='ACTIVE';

  if not found then raise exception 'LISTING_NOT_FOUND'; end if;
  return jsonb_build_object('success',true,'listing_id',p_listing_id,'status','CLOSED');
end;
$function$;

create or replace function public.participant_close_market_listing(p_listing_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.auth_user_id=(select auth.uid()) and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_LINKED'; end if;
  return private.prisma_participant_close_market_listing(uid,p_listing_id);
end;
$function$;

revoke all on function public.participant_close_market_listing(uuid) from public,anon;
grant execute on function public.participant_close_market_listing(uuid) to authenticated;
