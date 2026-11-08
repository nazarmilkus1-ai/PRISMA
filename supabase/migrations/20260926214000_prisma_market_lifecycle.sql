-- PRISMA market lifecycle: expire listings consistently even if a worker is delayed.

CREATE OR REPLACE FUNCTION private.prisma_participant_get_market(
  p_user_id uuid,
  p_kind text DEFAULT NULL,
  p_query text DEFAULT '',
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare q text:=trim(coalesce(p_query,''));
begin
  perform private.prisma_participant_require_access(p_user_id);
  if length(q)>64 then q:=left(q,64); end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select ml.id,ml.seller_id,ml.kind,ml.title,ml.description,ml.terms,ml.price_text,
             ml.status,ml.created_at,ml.updated_at,ml.expires_at,
             u.minecraft_nickname
      from public.market_listings ml
      join public.users u on u.id=ml.seller_id
      where ml.status='ACTIVE'
        and (ml.expires_at is null or ml.expires_at>now())
        and u.deleted_at is null and u.status='ACCEPTED' and not u.is_banned
        and (nullif(trim(coalesce(p_kind,'')),'') is null or ml.kind=trim(p_kind))
        and (q='' or ml.title ilike '%'||q||'%' or coalesce(ml.description,'') ilike '%'||q||'%')
      order by ml.created_at desc
      limit greatest(1,least(coalesce(p_limit,100),200))
    ) x
  ),'[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION private.prisma_participant_update_market_listing(
  p_user_id uuid,
  p_listing_id uuid,
  p_kind text,
  p_title text,
  p_description text,
  p_price_text text,
  p_terms text,
  p_expires_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
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
  set kind=v_kind,
      title=v_title,
      description=nullif(v_description,''),
      price_text=nullif(v_price,''),
      terms=nullif(v_terms,''),
      expires_at=p_expires_at,
      updated_at=now()
  where id=p_listing_id
    and seller_id=p_user_id
    and status='ACTIVE';

  if not found then raise exception 'LISTING_NOT_FOUND'; end if;

  return jsonb_build_object(
    'success',true,'listing_id',p_listing_id,'status','ACTIVE','expires_at',p_expires_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.participant_update_market_listing(
  p_listing_id uuid,
  p_kind text,
  p_title text,
  p_description text DEFAULT NULL,
  p_price_text text DEFAULT NULL,
  p_terms text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
declare uid uuid;
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

REVOKE ALL ON FUNCTION public.participant_update_market_listing(uuid,text,text,text,text,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.participant_update_market_listing(uuid,text,text,text,text,text,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.prisma_run_maintenance()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  expired int:=0;
  events int:=0;
  market_expired int:=0;
  metric_rows int:=0;
  activity_rows int:=0;
begin
  expired:=public.expire_punishments();
  events:=public.publish_scheduled_events();

  update public.market_listings
  set status='EXPIRED',updated_at=now()
  where status='ACTIVE'
    and expires_at is not null
    and expires_at<=now();
  get diagnostics market_expired = row_count;

  delete from public.idempotency_keys where expires_at<=now();
  delete from public.login_rate_limits where window_started_at < now()-interval '1 day';

  delete from public.server_metrics
  where recorded_at < now()-interval '30 days';
  get diagnostics metric_rows = row_count;

  delete from public.activity_events
  where created_at < now()-interval '90 days';
  get diagnostics activity_rows = row_count;

  return json_build_object(
    'expired_punishments',expired,
    'events_updated',events,
    'market_listings_expired',market_expired,
    'server_metrics_deleted',metric_rows,
    'activity_events_deleted',activity_rows
  );
end;
$function$;
