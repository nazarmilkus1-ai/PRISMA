create type news_kind as enum ('NEWS', 'UPDATE');

create table news (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  body         text not null,
  kind         news_kind not null default 'NEWS',
  is_published boolean not null default true,
  created_by_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index news_kind_idx on news (kind);
create index news_published_idx on news (is_published, created_at desc);

create trigger news_set_updated_at before update on news for each row execute function set_updated_at();

alter table news enable row level security;
create policy "admins can read news" on news for select to authenticated using (true);
alter publication supabase_realtime add table news;
