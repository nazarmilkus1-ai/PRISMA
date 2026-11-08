-- PRISMA Telegram market bridge: trusted bot contracts over the participant market domain.

create or replace function public.bot_get_market(p_tg_id bigint,p_kind text default null,p_query text default '',p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then return jsonb_build_object('error','USER_NOT_FOUND'); end if;
  return private.prisma_participant_get_market(uid,p_kind,p_query,p_limit);
end;
$function$;

create or replace function public.bot_get_market_inquiries(p_tg_id bigint)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then return jsonb_build_object('error','USER_NOT_FOUND'); end if;
  return private.prisma_participant_get_market_inquiries(uid);
end;
$function$;

create or replace function public.bot_create_market_listing(
  p_tg_id bigint,p_kind text,p_title text,p_description text default null,p_price_text text default null,p_terms text default null,p_expires_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_create_market_listing(uid,p_kind,p_title,p_description,p_price_text,p_terms,p_expires_at);
end;
$function$;

create or replace function public.bot_create_market_inquiry(p_tg_id bigint,p_listing_id uuid,p_message text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_create_market_inquiry(uid,p_listing_id,p_message);
end;
$function$;

create or replace function public.bot_respond_market_inquiry(p_tg_id bigint,p_inquiry_id uuid,p_response text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_respond_market_inquiry(uid,p_inquiry_id,p_response);
end;
$function$;

create or replace function public.bot_close_market_inquiry(p_tg_id bigint,p_inquiry_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_close_market_inquiry(uid,p_inquiry_id);
end;
$function$;

create or replace function public.bot_close_market_listing(p_tg_id bigint,p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare uid uuid;
begin
  select u.id into uid from public.users u where u.telegram_id=p_tg_id and u.deleted_at is null limit 1;
  if uid is null then raise exception 'USER_NOT_FOUND'; end if;
  return private.prisma_participant_close_market_listing(uid,p_listing_id);
end;
$function$;

revoke all on function public.bot_get_market(bigint,text,text,integer) from public,anon,authenticated;
revoke all on function public.bot_get_market_inquiries(bigint) from public,anon,authenticated;
revoke all on function public.bot_create_market_listing(bigint,text,text,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.bot_create_market_inquiry(bigint,uuid,text) from public,anon,authenticated;
revoke all on function public.bot_respond_market_inquiry(bigint,uuid,text) from public,anon,authenticated;
revoke all on function public.bot_close_market_inquiry(bigint,uuid) from public,anon,authenticated;
revoke all on function public.bot_close_market_listing(bigint,uuid) from public,anon,authenticated;

grant execute on function public.bot_get_market(bigint,text,text,integer) to service_role;
grant execute on function public.bot_get_market_inquiries(bigint) to service_role;
grant execute on function public.bot_create_market_listing(bigint,text,text,text,text,text,timestamptz) to service_role;
grant execute on function public.bot_create_market_inquiry(bigint,uuid,text) to service_role;
grant execute on function public.bot_respond_market_inquiry(bigint,uuid,text) to service_role;
grant execute on function public.bot_close_market_inquiry(bigint,uuid) to service_role;
grant execute on function public.bot_close_market_listing(bigint,uuid) to service_role;