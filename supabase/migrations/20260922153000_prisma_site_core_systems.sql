create table if not exists public.player_stats (
  user_id uuid primary key references public.users(id) on delete cascade,
  kills integer not null default 0 check (kills >= 0),
  deaths integer not null default 0 check (deaths >= 0),
  playtime_minutes bigint not null default 0 check (playtime_minutes >= 0),
  blocks_placed bigint not null default 0 check (blocks_placed >= 0),
  blocks_broken bigint not null default 0 check (blocks_broken >= 0),
  mobs_killed bigint not null default 0 check (mobs_killed >= 0),
  distance_walked bigint not null default 0 check (distance_walked >= 0),
  damage_dealt bigint not null default 0 check (damage_dealt >= 0),
  damage_taken bigint not null default 0 check (damage_taken >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.rating_history (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.users(id) on delete cascade,
  rating integer not null, delta integer not null default 0, reason text not null, season_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.player_battles (
  id uuid primary key default gen_random_uuid(), challenger_id uuid not null references public.users(id) on delete cascade,
  opponent_id uuid not null references public.users(id) on delete cascade, challenger_score bigint not null default 0,
  opponent_score bigint not null default 0, winner_id uuid references public.users(id) on delete set null,
  points_awarded integer not null default 0, status text not null default 'COMPLETED' check(status in('PENDING','COMPLETED','CANCELLED')),
  created_at timestamptz not null default now(), check(challenger_id <> opponent_id)
);
create table if not exists public.seasons (
  id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique,
  status text not null default 'UPCOMING' check(status in('UPCOMING','ACTIVE','FINISHED')),
  starts_at timestamptz, ends_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.season_ratings (
  id uuid primary key default gen_random_uuid(), season_id uuid not null references public.seasons(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade, rating integer not null default 0,
  points integer not null default 0, rank integer, updated_at timestamptz not null default now(), unique(season_id,user_id)
);
create table if not exists public.map_markers (
  id uuid primary key default gen_random_uuid(), kind text not null check(kind in('SPAWN','CITY','IMPORTANT','EVENT','CLAN')),
  title text not null, description text, world text not null default 'world', x double precision not null,
  y double precision not null default 64, z double precision not null, icon text, color text,
  clan_id uuid references public.clans(id) on delete set null, event_id uuid references public.events(id) on delete set null,
  created_by uuid references public.users(id) on delete set null, visible boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.map_history (
  id uuid primary key default gen_random_uuid(), marker_id uuid references public.map_markers(id) on delete set null,
  action text not null, snapshot jsonb not null default '{}'::jsonb, created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.market_listings (
  id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.users(id) on delete cascade,
  kind text not null check(kind in('SELL','BUY','TRADE','SERVICE','OTHER')), title text not null,
  description text, terms text, price_text text,
  status text not null default 'ACTIVE' check(status in('ACTIVE','RESERVED','CLOSED','EXPIRED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), expires_at timestamptz
);
create table if not exists public.timeline_events (
  id uuid primary key default gen_random_uuid(), kind text not null, title text not null, body text,
  occurred_at timestamptz not null default now(), actor_user_id uuid references public.users(id) on delete set null,
  clan_id uuid references public.clans(id) on delete set null, event_id uuid references public.events(id) on delete set null,
  marker_id uuid references public.map_markers(id) on delete set null, metadata jsonb not null default '{}'::jsonb
);
create table if not exists public.clan_achievements (
  clan_id uuid not null references public.clans(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(), primary key(clan_id,achievement_id)
);
create table if not exists public.awards (
  id uuid primary key default gen_random_uuid(), season_id uuid references public.seasons(id) on delete set null,
  name text not null, description text, kind text not null,
  target_type text not null check(target_type in('USER','CLAN','EVENT')), target_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.media_items (
  id uuid primary key default gen_random_uuid(), title text not null, url text not null,
  kind text not null check(kind in('IMAGE','VIDEO','OTHER')), description text, published_at timestamptz,
  created_by uuid references public.users(id) on delete set null, created_at timestamptz not null default now()
);
create table if not exists public.wiki_pages (
  id uuid primary key default gen_random_uuid(), slug text not null unique, title text not null,
  excerpt text, content text not null, category text not null default 'GENERAL', published boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.server_snapshots (
  id uuid primary key default gen_random_uuid(), node_id text not null references public.server_nodes(node_id) on delete cascade,
  online_players integer not null default 0, max_players integer not null default 0, tps numeric(6,2), mspt numeric(8,2),
  recorded_at timestamptz not null default now()
);
alter table public.player_stats enable row level security;
alter table public.rating_history enable row level security;
alter table public.player_battles enable row level security;
alter table public.seasons enable row level security;
alter table public.season_ratings enable row level security;
alter table public.map_markers enable row level security;
alter table public.map_history enable row level security;
alter table public.market_listings enable row level security;
alter table public.timeline_events enable row level security;
alter table public.clan_achievements enable row level security;
alter table public.awards enable row level security;
alter table public.media_items enable row level security;
alter table public.wiki_pages enable row level security;
alter table public.server_snapshots enable row level security;

do $$
begin
  execute 'drop policy if exists player_stats_member_select on public.player_stats';
  execute 'drop policy if exists rating_history_member_select on public.rating_history';
  execute 'drop policy if exists player_battles_member_select on public.player_battles';
  execute 'drop policy if exists seasons_member_select on public.seasons';
  execute 'drop policy if exists season_ratings_member_select on public.season_ratings';
  execute 'drop policy if exists map_markers_member_select on public.map_markers';
  execute 'drop policy if exists map_history_member_select on public.map_history';
  execute 'drop policy if exists market_member_select on public.market_listings';
  execute 'drop policy if exists market_member_insert on public.market_listings';
  execute 'drop policy if exists timeline_member_select on public.timeline_events';
  execute 'drop policy if exists clan_achievements_member_select on public.clan_achievements';
  execute 'drop policy if exists awards_member_select on public.awards';
  execute 'drop policy if exists media_public_select on public.media_items';
  execute 'drop policy if exists wiki_public_select on public.wiki_pages';
  execute 'drop policy if exists server_snapshots_member_select on public.server_snapshots';
end $$;
create policy player_stats_member_select on public.player_stats for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy rating_history_member_select on public.rating_history for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy player_battles_member_select on public.player_battles for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy seasons_member_select on public.seasons for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy season_ratings_member_select on public.season_ratings for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy map_markers_member_select on public.map_markers for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy map_history_member_select on public.map_history for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy market_member_select on public.market_listings for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy market_member_insert on public.market_listings for insert to authenticated with check (exists(select 1 from public.users u where u.id=seller_id and u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy timeline_member_select on public.timeline_events for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy clan_achievements_member_select on public.clan_achievements for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy awards_member_select on public.awards for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create policy media_public_select on public.media_items for select to anon,authenticated using (published_at is not null and published_at<=now());
create policy wiki_public_select on public.wiki_pages for select to anon,authenticated using (published=true);
create policy server_snapshots_member_select on public.server_snapshots for select to authenticated using (exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.status='ACCEPTED'::public.application_status and not u.is_banned));
create index if not exists idx_rating_history_user_created on public.rating_history(user_id,created_at desc);
create index if not exists idx_player_battles_users_created on public.player_battles(challenger_id,opponent_id,created_at desc);
create index if not exists idx_season_ratings_season_rank on public.season_ratings(season_id,rank);
create index if not exists idx_map_markers_visible_kind on public.map_markers(visible,kind);
create index if not exists idx_market_status_created on public.market_listings(status,created_at desc);
create index if not exists idx_timeline_occurred on public.timeline_events(occurred_at desc);
create index if not exists idx_server_snapshots_node_recorded on public.server_snapshots(node_id,recorded_at desc);
