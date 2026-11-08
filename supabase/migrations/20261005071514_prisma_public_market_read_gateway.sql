create or replace function private.prisma_public_get_market(
  p_kind text default null,
  p_query text default '',
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  q text := left(trim(coalesce(p_query,'')),64);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select
        ml.id,
        ml.kind,
        ml.title,
        ml.description,
        ml.terms,
        ml.price_text,
        ml.status,
        ml.created_at,
        ml.updated_at,
        ml.expires_at,
        u.minecraft_nickname
      from public.market_listings ml
      join public.users u on u.id = ml.seller_id
      where ml.status = 'ACTIVE'
        and (ml.expires_at is null or ml.expires_at > now())
        and u.deleted_at is null
        and u.status = 'ACCEPTED'
        and not u.is_banned
        and (
          nullif(trim(coalesce(p_kind,'')),'') is null
          or ml.kind = trim(p_kind)
        )
        and (
          q = ''
          or ml.title ilike '%' || q || '%'
          or ml.description ilike '%' || q || '%'
          or ml.price_text ilike '%' || q || '%'
          or ml.terms ilike '%' || q || '%'
        )
      order by ml.created_at desc
      limit greatest(1, least(coalesce(p_limit,100),200))
    ) x
  ), '[]'::jsonb);
end;
$function$;

revoke all on function private.prisma_public_get_market(text,text,integer) from public, anon, authenticated;
grant execute on function private.prisma_public_get_market(text,text,integer) to anon, authenticated;

create or replace function public.get_public_market(
  p_kind text default null,
  p_query text default '',
  p_limit integer default 100
)
returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select private.prisma_public_get_market(p_kind,p_query,p_limit);
$function$;

revoke all on function public.get_public_market(text,text,integer) from public, anon, authenticated;
grant execute on function public.get_public_market(text,text,integer) to anon, authenticated;