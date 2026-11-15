-- Event entry fees and prizes in PRISMA Points.
-- PvP championship: fee 10 PP; Judgement Day: fee 10 PP; Mafia: free (fee 0, no prize).
-- Prize: the winner takes the pool minus the project commission (default 10%), paid once.
-- Forward-only. Not applied to production by the repository change.

alter table public.events
  add column if not exists entry_fee_pp integer not null default 0 check (entry_fee_pp between 0 and 100000),
  add column if not exists commission_pct integer not null default 10 check (commission_pct between 0 and 50),
  add column if not exists prize_paid_at timestamptz,
  add column if not exists prize_user_id uuid references public.users(id) on delete set null;
alter table public.event_participants
  add column if not exists fee_paid integer not null default 0 check (fee_paid >= 0);

create or replace function private.prisma_participant_register_event(p_user_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  e public.events%rowtype;
  count_now integer;
  v_nickname text;
  v_telegram_id bigint;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select * into e from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if e.status not in ('scheduled','live','published','registration','open','active') then
    raise exception 'EVENT_NOT_OPEN';
  end if;

  if e.registration_deadline is not null and e.registration_deadline<=now() then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  if exists(
    select 1 from public.event_participants ep
    where ep.event_id=p_event_id and ep.user_id=p_user_id
  ) then
    return jsonb_build_object('success',true,'duplicate',true,'registered',true,'event_id',p_event_id);
  end if;

  if e.max_participants is not null then
    select count(*) into count_now from public.event_participants ep where ep.event_id=p_event_id;
    if count_now>=e.max_participants then raise exception 'EVENT_FULL'; end if;
  end if;

  -- The fee is charged in the same transaction: a failed charge (INSUFFICIENT_PP) leaves no registration behind.
  if e.entry_fee_pp > 0 then
    perform private.pp_apply(p_user_id, -e.entry_fee_pp, 'event_fee', p_event_id::text || ':' || gen_random_uuid()::text, e.title);
  end if;

  insert into public.event_participants(event_id,user_id,fee_paid)
  values(p_event_id,p_user_id,e.entry_fee_pp);

  select minecraft_nickname,telegram_id into v_nickname,v_telegram_id
  from public.users where id=p_user_id limit 1;

  insert into public.notifications(
    user_id,telegram_id,channel,kind,title,body,data,status,available_at
  )
  values(
    p_user_id,v_telegram_id,'telegram','EVENT',
    'Регистрация подтверждена',
    'Вы зарегистрированы на событие "'||e.title||'"'||
      case when e.entry_fee_pp > 0 then ' (взнос '||e.entry_fee_pp||' PP).' else '.' end,
    jsonb_build_object(
      'event_id',e.id,'slug',e.slug,'nickname',v_nickname,'source','event_registration'
    ),
    'pending',now()
  );

  return jsonb_build_object(
    'success',true,'duplicate',false,'registered',true,'event_id',p_event_id,'fee_paid',e.entry_fee_pp
  );
end;
$function$;

create or replace function private.prisma_participant_unregister_event(p_user_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  e public.events%rowtype;
  paid integer;
begin
  perform private.prisma_participant_require_access(p_user_id);

  select * into e from public.events where id=p_event_id for update;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;

  if e.status in ('live','finished','cancelled') then
    raise exception 'EVENT_ALREADY_STARTED';
  end if;
  if e.starts_at is not null and e.starts_at<=now() then
    raise exception 'EVENT_ALREADY_STARTED';
  end if;
  if e.registration_deadline is not null and e.registration_deadline<=now() then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  delete from public.event_participants ep
  where ep.event_id=p_event_id and ep.user_id=p_user_id
  returning ep.fee_paid into paid;

  if not found then raise exception 'REGISTRATION_NOT_FOUND'; end if;
  if coalesce(paid, 0) > 0 then
    perform private.pp_apply(p_user_id, paid, 'refund', p_event_id::text || ':' || gen_random_uuid()::text, e.title);
  end if;
  return jsonb_build_object('success',true,'registered',false,'event_id',p_event_id,'refunded',coalesce(paid, 0));
end;
$function$;

create or replace function public.bot_list_events(p_tg_id bigint, p_limit integer default 20)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  uid uuid;
begin
  select id into uid from public.users
  where telegram_id=p_tg_id and deleted_at is null
  limit 1;
  if uid is null then return json_build_object('error','USER_NOT_FOUND'); end if;

  return coalesce((
    select json_agg(x order by x.starts_at asc nulls last)
    from (
      select
        e.id,e.slug,e.title,e.description,e.status,e.starts_at,e.ends_at,
        e.registration_deadline,e.max_participants,e.reward_config,e.entry_fee_pp,
        exists(
          select 1 from public.event_participants ep
          where ep.event_id=e.id and ep.user_id=uid
        ) as registered,
        (
          select count(*)::integer
          from public.event_participants ep
          where ep.event_id=e.id
        ) as participant_count
      from public.events e
      where e.status in ('scheduled','live')
      order by e.starts_at asc nulls last
      limit greatest(1,least(coalesce(p_limit,20),50))
    ) x
  ),'[]'::json);
end;
$function$;

-- Staff: set the entry fee of an event (by id or slug). Only before anyone has paid a different fee.
create or replace function public.bot_event_set_fee(p_tg_id bigint, p_event text, p_fee integer)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  me uuid := private.get_user_by_tg_id(p_tg_id);
  ev public.events%rowtype;
begin
  if me is null or not private.prisma_has_user_permission(me, 'economy.manage') then
    return json_build_object('success', false, 'error', 'PERMISSION_DENIED');
  end if;
  if p_fee is null or p_fee < 0 or p_fee > 100000 then return json_build_object('success', false, 'error', 'INVALID_AMOUNT'); end if;
  select * into ev from public.events e
    where e.slug = btrim(p_event) or (btrim(p_event) ~ '^[0-9a-f-]{36}$' and e.id = btrim(p_event)::uuid) limit 1;
  if not found then return json_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); end if;
  if exists (select 1 from public.event_participants ep where ep.event_id = ev.id and ep.fee_paid <> p_fee and ep.fee_paid > 0) then
    return json_build_object('success', false, 'error', 'FEES_ALREADY_PAID');
  end if;
  update public.events set entry_fee_pp = p_fee, updated_at = now() where id = ev.id;
  return json_build_object('success', true, 'event', ev.title, 'fee', p_fee);
end;
$function$;

-- Staff: pay the prize. Pool = fees actually paid; commission stays with the project; one payout per event.
create or replace function public.bot_event_payout(p_tg_id bigint, p_event text, p_winner text)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  me uuid := private.get_user_by_tg_id(p_tg_id);
  winner uuid := private.pp_resolve_target(p_winner);
  ev public.events%rowtype;
  pool bigint;
  commission bigint;
  prize bigint;
  bal bigint;
begin
  if me is null or not private.prisma_has_user_permission(me, 'economy.manage') then
    return json_build_object('success', false, 'error', 'PERMISSION_DENIED');
  end if;
  select * into ev from public.events e
    where e.slug = btrim(p_event) or (btrim(p_event) ~ '^[0-9a-f-]{36}$' and e.id = btrim(p_event)::uuid)
    limit 1 for update;
  if not found then return json_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); end if;
  if ev.prize_paid_at is not null then return json_build_object('success', false, 'error', 'ALREADY_PAID'); end if;
  if winner is null or not exists (select 1 from public.event_participants ep where ep.event_id = ev.id and ep.user_id = winner) then
    return json_build_object('success', false, 'error', 'WINNER_NOT_PARTICIPANT');
  end if;
  select coalesce(sum(ep.fee_paid), 0) into pool from public.event_participants ep where ep.event_id = ev.id;
  commission := (pool * ev.commission_pct) / 100;
  prize := pool - commission;
  if prize > 0 then
    bal := private.pp_apply(winner, prize, 'event_prize', ev.id::text, ev.title, me);
  end if;
  update public.event_participants set placement = 1 where event_id = ev.id and user_id = winner;
  update public.events set prize_paid_at = now(), prize_user_id = winner, status = 'finished', updated_at = now() where id = ev.id;
  return json_build_object('success', true, 'event', ev.title, 'pool', pool, 'commission', commission, 'prize', prize);
end;
$function$;

revoke all on function public.bot_event_set_fee(bigint,text,integer) from public, anon, authenticated;
grant execute on function public.bot_event_set_fee(bigint,text,integer) to service_role;
revoke all on function public.bot_event_payout(bigint,text,text) from public, anon, authenticated;
grant execute on function public.bot_event_payout(bigint,text,text) to service_role;
revoke all on function public.bot_list_events(bigint,integer) from public, anon, authenticated;
grant execute on function public.bot_list_events(bigint,integer) to service_role;
