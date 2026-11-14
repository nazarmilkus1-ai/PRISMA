-- PRISMA Points: selling resources to the server and a small shop. Prices live in the database (editable without a release).
-- The plugin takes items from the player first, then calls these RPCs; on failure it hands the items back.
-- Forward-only. Not applied to production by the repository change.

create table if not exists public.pp_sell_prices (
  item text primary key check (item ~ '^[A-Z0-9_]{3,64}$'),   -- Bukkit Material name
  title text not null,
  pp_per_16 integer not null check (pp_per_16 between 1 and 100000),
  daily_cap integer not null default 640 check (daily_cap between 1 and 100000),
  active boolean not null default true
);
create table if not exists public.pp_sell_daily (
  user_id uuid not null references public.users(id) on delete cascade,
  day date not null default (now() at time zone 'utc')::date,
  item text not null,
  qty integer not null default 0,
  primary key (user_id, day, item)
);
create table if not exists public.pp_shop_items (
  sku text primary key check (sku ~ '^[a-z0-9_]{3,40}$'),
  title text not null,
  description text,
  price integer not null check (price between 1 and 1000000),
  kind text not null check (kind in ('effect')),
  payload jsonb not null default '{}'::jsonb,   -- effect: {"effect":"SPEED","seconds":1800,"amplifier":0}
  active boolean not null default true,
  sort integer not null default 0
);
create table if not exists public.pp_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  sku text not null references public.pp_shop_items(sku),
  price integer not null,
  status text not null default 'paid' check (status in ('paid','refunded')),
  created_at timestamptz not null default now()
);
create index if not exists pp_purchases_user_idx on public.pp_purchases(user_id, created_at desc);

alter table public.pp_sell_prices enable row level security;
alter table public.pp_sell_daily enable row level security;
alter table public.pp_shop_items enable row level security;
alter table public.pp_purchases enable row level security;
revoke all on public.pp_sell_prices, public.pp_sell_daily, public.pp_shop_items, public.pp_purchases from public, anon, authenticated;
grant select, insert, update on public.pp_sell_prices, public.pp_sell_daily, public.pp_shop_items, public.pp_purchases to service_role;

insert into public.pp_sell_prices(item, title, pp_per_16, daily_cap) values
  ('COAL','Уголь',2,1280), ('COPPER_INGOT','Медь',2,1280), ('IRON_INGOT','Железо',4,640),
  ('GOLD_INGOT','Золото',6,640), ('LAPIS_LAZULI','Лазурит',2,1280), ('REDSTONE','Редстоун',2,1280),
  ('EMERALD','Изумруд',16,256), ('DIAMOND','Алмаз',32,128)
on conflict (item) do nothing;
insert into public.pp_shop_items(sku, title, description, price, kind, payload, sort) values
  ('speed_30','Скорость · 30 мин','Эффект «Скорость» на 30 минут',10,'effect','{"effect":"SPEED","seconds":1800,"amplifier":0}',10),
  ('haste_30','Спешка · 30 мин','Быстрая добыча на 30 минут',15,'effect','{"effect":"HASTE","seconds":1800,"amplifier":0}',20),
  ('night_30','Ночное зрение · 30 мин','Видно в темноте 30 минут',8,'effect','{"effect":"NIGHT_VISION","seconds":1800,"amplifier":0}',30),
  ('regen_10','Регенерация · 10 мин','Восстановление здоровья 10 минут',12,'effect','{"effect":"REGENERATION","seconds":600,"amplifier":0}',40)
on conflict (sku) do nothing;

-- Current member only (accepted application), identified by the profile id the plugin already caches.
create or replace function private.pp_member(p_user_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $function$
  select exists (select 1 from public.users u where u.id = p_user_id and u.deleted_at is null and u.status::text = 'ACCEPTED');
$function$;
revoke all on function private.pp_member(uuid) from public, anon, authenticated;

create or replace function public.mc_pp_catalog(p_user_id uuid)
returns json
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not private.pp_member(p_user_id) then return json_build_object('success', false, 'error', 'NOT_A_MEMBER'); end if;
  return json_build_object('success', true,
    'balance', coalesce((select balance from public.pp_accounts where user_id = p_user_id), 0),
    'sell', coalesce((select json_agg(json_build_object('item', s.item, 'title', s.title, 'pp_per_16', s.pp_per_16,
        'cap_left', greatest(s.daily_cap - coalesce(d.qty, 0), 0)) order by s.pp_per_16)
      from public.pp_sell_prices s
      left join public.pp_sell_daily d on d.user_id = p_user_id and d.item = s.item and d.day = (now() at time zone 'utc')::date
      where s.active), '[]'::json),
    'shop', coalesce((select json_agg(json_build_object('sku', i.sku, 'title', i.title, 'description', i.description,
        'price', i.price, 'kind', i.kind, 'payload', i.payload) order by i.sort)
      from public.pp_shop_items i where i.active), '[]'::json));
end;
$function$;

create or replace function public.mc_pp_sell(p_user_id uuid, p_item text, p_qty integer)
returns json
language plpgsql security definer set search_path=''
as $function$
declare
  price public.pp_sell_prices%rowtype;
  sold integer;
  paid bigint;
  bal bigint;
begin
  if not private.pp_member(p_user_id) then return json_build_object('success', false, 'error', 'NOT_A_MEMBER'); end if;
  if p_qty is null or p_qty < 1 or p_qty > 100000 then return json_build_object('success', false, 'error', 'INVALID_AMOUNT'); end if;
  select * into price from public.pp_sell_prices where item = upper(p_item) and active;
  if not found then return json_build_object('success', false, 'error', 'ITEM_NOT_SOLD'); end if;
  insert into public.pp_sell_daily(user_id, day, item, qty) values (p_user_id, (now() at time zone 'utc')::date, price.item, 0)
    on conflict do nothing;
  select qty into sold from public.pp_sell_daily
    where user_id = p_user_id and day = (now() at time zone 'utc')::date and item = price.item for update;
  if sold + p_qty > price.daily_cap then
    return json_build_object('success', false, 'error', 'DAILY_CAP', 'cap_left', greatest(price.daily_cap - sold, 0));
  end if;
  paid := (p_qty::bigint * price.pp_per_16) / 16;
  if paid < 1 then return json_build_object('success', false, 'error', 'TOO_FEW'); end if;
  bal := private.pp_apply(p_user_id, paid, 'sell', null, p_qty || ' x ' || price.item);
  update public.pp_sell_daily set qty = qty + p_qty
    where user_id = p_user_id and day = (now() at time zone 'utc')::date and item = price.item;
  return json_build_object('success', true, 'paid', paid, 'balance', bal, 'cap_left', price.daily_cap - sold - p_qty);
end;
$function$;

create or replace function public.mc_pp_buy(p_user_id uuid, p_sku text)
returns json
language plpgsql security definer set search_path=''
as $function$
declare
  item public.pp_shop_items%rowtype;
  purchase uuid;
  bal bigint;
begin
  if not private.pp_member(p_user_id) then return json_build_object('success', false, 'error', 'NOT_A_MEMBER'); end if;
  select * into item from public.pp_shop_items where sku = p_sku and active;
  if not found then return json_build_object('success', false, 'error', 'ITEM_NOT_FOUND'); end if;
  purchase := gen_random_uuid();
  begin
    bal := private.pp_apply(p_user_id, -item.price, 'shop', purchase::text, item.sku);
  exception when others then
    if sqlerrm = 'INSUFFICIENT_PP' then return json_build_object('success', false, 'error', 'INSUFFICIENT_PP'); end if;
    raise;
  end;
  insert into public.pp_purchases(id, user_id, sku, price) values (purchase, p_user_id, item.sku, item.price);
  return json_build_object('success', true, 'purchase_id', purchase, 'balance', bal, 'kind', item.kind,
    'payload', item.payload, 'title', item.title);
end;
$function$;

-- The plugin calls this when it could not deliver what was bought.
create or replace function public.mc_pp_refund(p_user_id uuid, p_purchase_id uuid)
returns json
language plpgsql security definer set search_path=''
as $function$
declare
  row public.pp_purchases%rowtype;
  bal bigint;
begin
  select * into row from public.pp_purchases where id = p_purchase_id and user_id = p_user_id for update;
  if not found then return json_build_object('success', false, 'error', 'NOT_FOUND'); end if;
  if row.status = 'refunded' then return json_build_object('success', true, 'already', true); end if;
  bal := private.pp_apply(p_user_id, row.price, 'refund', p_purchase_id::text, row.sku);
  update public.pp_purchases set status = 'refunded' where id = p_purchase_id;
  return json_build_object('success', true, 'balance', bal);
end;
$function$;

revoke all on function public.mc_pp_catalog(uuid) from public, anon, authenticated;
grant execute on function public.mc_pp_catalog(uuid) to service_role;
revoke all on function public.mc_pp_sell(uuid,text,integer) from public, anon, authenticated;
grant execute on function public.mc_pp_sell(uuid,text,integer) to service_role;
revoke all on function public.mc_pp_buy(uuid,text) from public, anon, authenticated;
grant execute on function public.mc_pp_buy(uuid,text) to service_role;
revoke all on function public.mc_pp_refund(uuid,uuid) from public, anon, authenticated;
grant execute on function public.mc_pp_refund(uuid,uuid) to service_role;
