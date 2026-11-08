-- PRISMA v2: canonical participant-owned market listing read gateway.
create or replace function public.participant_get_market_listing(p_listing_id uuid)
returns jsonb
language sql
security definer
set search_path to ''
as $function$
select coalesce(
  (
    select jsonb_build_object(
      'id', l.id,
      'seller_id', l.seller_id,
      'kind', l.kind,
      'title', l.title,
      'description', l.description,
      'terms', l.terms,
      'price_text', l.price_text,
      'status', l.status,
      'created_at', l.created_at,
      'updated_at', l.updated_at,
      'expires_at', l.expires_at
    )
    from public.market_listings l
    where l.id = p_listing_id
      and l.seller_id = (
        select u.id
        from public.users u
        where u.auth_user_id = (select auth.uid())
          and u.deleted_at is null
        limit 1
      )
    limit 1
  ),
  null
);
$function$;

revoke execute on function public.participant_get_market_listing(uuid) from public, anon;
grant execute on function public.participant_get_market_listing(uuid) to authenticated;
grant execute on function public.participant_get_market_listing(uuid) to postgres;
