-- PRISMA Points (PP): one balance per profile, every change is a ledger row.
-- Forward-only. Not applied to production by the repository change.
-- Balance never goes negative; (kind, ref) makes a repeated call with the same ref a no-op (idempotent rewards/refunds).

create table if not exists public.pp_accounts (
  user_id uuid primary key references public.users(id) on delete cascade,
  balance bigint not null default 0 constraint pp_accounts_balance_nonneg check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.pp_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  delta bigint not null constraint pp_ledger_delta_nonzero check (delta <> 0),
  balance_after bigint not null constraint pp_ledger_after_nonneg check (balance_after >= 0),
  kind text not null,               -- transfer_in/out, event_fee, event_prize, shop, sell, reward, admin, refund, commission
  ref text,                         -- idempotency key / external reference (event id, order id ...)
  note text,
  actor_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists pp_ledger_user_idx on public.pp_ledger(user_id, id desc);
create unique index if not exists pp_ledger_kind_ref_unique on public.pp_ledger(kind, ref, user_id) where ref is not null;

alter table public.pp_accounts enable row level security;
alter table public.pp_ledger enable row level security;
revoke all on public.pp_accounts, public.pp_ledger from public, anon, authenticated;
grant select, insert, update on public.pp_accounts to service_role;
grant select, insert on public.pp_ledger to service_role;

insert into public.permissions(key,description)
values ('economy.manage','Выдача и списание PRISMA Points, просмотр баланса игроков')
on conflict (key) do update set description=excluded.description;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where p.key='economy.manage' and r.name in ('owner','head_admin','head_staff','admin')
on conflict do nothing;

-- Single entry point for every balance change. Returns the new balance, or raises INSUFFICIENT_PP / INVALID_AMOUNT.
-- A repeated (kind, ref) for the same user returns the current balance and changes nothing.
create or replace function private.pp_apply(
  p_user_id uuid, p_delta bigint, p_kind text, p_ref text default null, p_note text default null, p_actor uuid default null
) returns bigint
language plpgsql
security definer
set search_path=''
as $function$
declare
  new_balance bigint;
begin
  if p_user_id is null or p_delta is null or p_delta = 0 or abs(p_delta) > 1000000000 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if p_ref is not null and exists (
    select 1 from public.pp_ledger l where l.kind = p_kind and l.ref = p_ref and l.user_id = p_user_id
  ) then
    return (select balance from public.pp_accounts where user_id = p_user_id);
  end if;

  insert into public.pp_accounts(user_id) values (p_user_id) on conflict (user_id) do nothing;
  update public.pp_accounts
     set balance = balance + p_delta, updated_at = now()
   where user_id = p_user_id and balance + p_delta >= 0
  returning balance into new_balance;
  if new_balance is null then
    raise exception 'INSUFFICIENT_PP';
  end if;

  insert into public.pp_ledger(user_id, delta, balance_after, kind, ref, note, actor_user_id)
  values (p_user_id, p_delta, new_balance, p_kind, p_ref, left(p_note, 300), p_actor);
  return new_balance;
end;
$function$;
revoke all on function private.pp_apply(uuid,bigint,text,text,text,uuid) from public, anon, authenticated;

create or replace function private.pp_resolve_target(p_target text)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select u.id from public.users u
  where u.deleted_at is null
    and (lower(u.telegram_username) = lower(ltrim(btrim(p_target), '@'))
      or lower(u.minecraft_nickname) = lower(btrim(p_target))
      or (case when btrim(p_target) ~ '^[0-9]{1,15}$' then u.telegram_id = btrim(p_target)::bigint else false end))
  order by (u.status::text = 'ACCEPTED') desc
  limit 1;
$function$;
revoke all on function private.pp_resolve_target(text) from public, anon, authenticated;

create or replace function public.bot_pp_balance(p_tg_id bigint)
returns json
language plpgsql
stable
security definer
set search_path=''
as $function$
declare uid uuid := private.get_user_by_tg_id(p_tg_id);
begin
  if uid is null then return json_build_object('success', false, 'error', 'USER_NOT_FOUND'); end if;
  return json_build_object('success', true,
    'balance', coalesce((select balance from public.pp_accounts where user_id = uid), 0));
end;
$function$;

create or replace function public.bot_pp_history(p_tg_id bigint, p_limit integer default 10)
returns json
language plpgsql
stable
security definer
set search_path=''
as $function$
declare uid uuid := private.get_user_by_tg_id(p_tg_id);
begin
  if uid is null then return json_build_object('success', false, 'error', 'USER_NOT_FOUND'); end if;
  return json_build_object('success', true,
    'balance', coalesce((select balance from public.pp_accounts where user_id = uid), 0),
    'items', coalesce((select json_agg(x) from (
      select l.delta, l.balance_after, l.kind, l.note, l.created_at
      from public.pp_ledger l where l.user_id = uid
      order by l.id desc limit least(greatest(coalesce(p_limit, 10), 1), 50)) x), '[]'::json));
end;
$function$;

create or replace function public.bot_pp_transfer(p_tg_id bigint, p_target text, p_amount bigint)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  me uuid := private.get_user_by_tg_id(p_tg_id);
  other uuid := private.pp_resolve_target(p_target);
  my_name text;
  other_name text;
  bal bigint;
begin
  if me is null then return json_build_object('success', false, 'error', 'USER_NOT_FOUND'); end if;
  if other is null then return json_build_object('success', false, 'error', 'TARGET_NOT_FOUND'); end if;
  if other = me then return json_build_object('success', false, 'error', 'SELF_TRANSFER'); end if;
  if p_amount is null or p_amount < 1 or p_amount > 100000 then
    return json_build_object('success', false, 'error', 'INVALID_AMOUNT');
  end if;
  if not exists (select 1 from public.users u where u.id = me and u.status::text = 'ACCEPTED') then
    return json_build_object('success', false, 'error', 'NOT_A_MEMBER');
  end if;
  select coalesce(nullif(u.telegram_username, ''), u.minecraft_nickname) into my_name from public.users u where u.id = me;
  select coalesce(nullif(u.telegram_username, ''), u.minecraft_nickname) into other_name from public.users u where u.id = other;
  begin
    bal := private.pp_apply(me, -p_amount, 'transfer_out', null, 'to ' || coalesce(other_name, '?'), me);
  exception when others then
    if sqlerrm = 'INSUFFICIENT_PP' then return json_build_object('success', false, 'error', 'INSUFFICIENT_PP'); end if;
    raise;
  end;
  perform private.pp_apply(other, p_amount, 'transfer_in', null, 'from ' || coalesce(my_name, '?'), me);
  return json_build_object('success', true, 'balance', bal, 'to', other_name, 'amount', p_amount);
end;
$function$;

create or replace function public.bot_pp_adjust(p_tg_id bigint, p_target text, p_delta bigint, p_note text default null)
returns json
language plpgsql
security definer
set search_path=''
as $function$
declare
  me uuid := private.get_user_by_tg_id(p_tg_id);
  other uuid := private.pp_resolve_target(p_target);
  bal bigint;
begin
  if me is null or not private.prisma_has_user_permission(me, 'economy.manage') then
    return json_build_object('success', false, 'error', 'PERMISSION_DENIED');
  end if;
  if other is null then return json_build_object('success', false, 'error', 'TARGET_NOT_FOUND'); end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 1000000 then
    return json_build_object('success', false, 'error', 'INVALID_AMOUNT');
  end if;
  begin
    bal := private.pp_apply(other, p_delta, 'admin', null, coalesce(nullif(btrim(p_note), ''), 'admin'), me);
  exception when others then
    if sqlerrm = 'INSUFFICIENT_PP' then return json_build_object('success', false, 'error', 'INSUFFICIENT_PP'); end if;
    raise;
  end;
  return json_build_object('success', true, 'balance', bal);
end;
$function$;

revoke all on function public.bot_pp_balance(bigint) from public, anon, authenticated;
grant execute on function public.bot_pp_balance(bigint) to service_role;
revoke all on function public.bot_pp_history(bigint,integer) from public, anon, authenticated;
grant execute on function public.bot_pp_history(bigint,integer) to service_role;
revoke all on function public.bot_pp_transfer(bigint,text,bigint) from public, anon, authenticated;
grant execute on function public.bot_pp_transfer(bigint,text,bigint) to service_role;
revoke all on function public.bot_pp_adjust(bigint,text,bigint,text) from public, anon, authenticated;
grant execute on function public.bot_pp_adjust(bigint,text,bigint,text) to service_role;
