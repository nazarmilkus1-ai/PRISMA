-- Autonomous development agent: goals, long-term memory, topic inbox, journal and state.
-- Everything is reachable only through service_role RPCs (the bot); tables have RLS on and no policies.

create table if not exists public.agent_state (
  id int primary key check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.agent_state(id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

create table if not exists public.agent_goals (
  id bigserial primary key,
  title text not null check (char_length(title) between 3 and 200),
  why text not null default '' check (char_length(why) <= 1500),
  expected text not null default '' check (char_length(expected) <= 1500),
  status text not null default 'active' check (status in ('active','done','dropped','paused')),
  tasks jsonb not null default '[]'::jsonb,
  progress_pct int not null default 0 check (progress_pct between 0 and 100),
  health_pct int check (health_pct is null or health_pct between 0 and 100),
  branch text check (branch is null or char_length(branch) <= 120),
  pr_number int,
  head_sha text,
  review jsonb not null default '{}'::jsonb,
  source text not null default 'agent',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  merged_at timestamptz
);
create index if not exists agent_goals_status_idx on public.agent_goals (status, updated_at desc);

create table if not exists public.agent_memory (
  id bigserial primary key,
  kind text not null default 'fact' check (kind in ('fact','lesson','user','decision','idea','core')),
  body text not null check (char_length(body) between 3 and 1500),
  tags text[] not null default '{}',
  importance smallint not null default 3 check (importance between 1 and 5),
  pinned boolean not null default false,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  fts tsvector generated always as (to_tsvector('simple', body)) stored
);
create index if not exists agent_memory_fts_idx on public.agent_memory using gin (fts);
create index if not exists agent_memory_rank_idx on public.agent_memory (pinned desc, importance desc, created_at desc);

create table if not exists public.agent_inbox (
  id bigserial primary key,
  tg_user_id bigint not null,
  username text check (username is null or char_length(username) <= 64),
  is_admin boolean not null default false,
  body text not null check (char_length(body) between 1 and 2000),
  tg_message_id bigint,
  handled boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists agent_inbox_open_idx on public.agent_inbox (handled, created_at);

create table if not exists public.agent_journal (
  id bigserial primary key,
  kind text not null check (kind in ('cycle','report','event','merge')),
  body text not null check (char_length(body) <= 4000),
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists agent_journal_created_idx on public.agent_journal (created_at desc);

alter table public.agent_state enable row level security;
alter table public.agent_goals enable row level security;
alter table public.agent_memory enable row level security;
alter table public.agent_inbox enable row level security;
alter table public.agent_journal enable row level security;
revoke all on public.agent_state, public.agent_goals, public.agent_memory, public.agent_inbox, public.agent_journal from public, anon, authenticated;
revoke all on sequence public.agent_goals_id_seq, public.agent_memory_id_seq, public.agent_inbox_id_seq, public.agent_journal_id_seq from public, anon, authenticated;

-- ---------- state ----------

create or replace function public.bot_agent_state_get()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select data from public.agent_state where id = 1), '{}'::jsonb)
$$;

create or replace function public.bot_agent_state_patch(p_patch jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  update public.agent_state set data = data || coalesce(p_patch, '{}'::jsonb), updated_at = now() where id = 1 returning data
$$;

-- Atomic "claim": true only for the one caller that finds last_<what> older than p_min_seconds (also guards against
-- two bot instances overlapping during a deploy).
create or replace function public.bot_agent_claim(p_what text, p_min_seconds int)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_ok boolean;
begin
  if p_what !~ '^[a-z_]{1,30}$' then raise exception 'BAD_CLAIM'; end if;
  update public.agent_state
     set data = data || jsonb_build_object('last_' || p_what, to_jsonb(now())), updated_at = now()
   where id = 1
     and (data ->> ('last_' || p_what) is null
          or (data ->> ('last_' || p_what))::timestamptz < now() - make_interval(secs => greatest(p_min_seconds, 1)))
  returning true into v_ok;
  return coalesce(v_ok, false);
end $$;

-- ---------- goals ----------

create or replace function public.bot_agent_goal_save(p_id bigint, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.agent_goals%rowtype; v_id bigint := p_id;
begin
  if v_id is null then
    insert into public.agent_goals(title, why, expected, source, tasks)
    values (left(coalesce(p_patch ->> 'title', 'Без названия'), 200), left(coalesce(p_patch ->> 'why', ''), 1500),
            left(coalesce(p_patch ->> 'expected', ''), 1500), coalesce(nullif(p_patch ->> 'source', ''), 'agent'),
            coalesce(p_patch -> 'tasks', '[]'::jsonb))
    returning id into v_id;
  end if;
  update public.agent_goals g set
    title = coalesce(left(p_patch ->> 'title', 200), g.title),
    why = coalesce(left(p_patch ->> 'why', 1500), g.why),
    expected = coalesce(left(p_patch ->> 'expected', 1500), g.expected),
    status = coalesce(p_patch ->> 'status', g.status),
    tasks = coalesce(p_patch -> 'tasks', g.tasks),
    progress_pct = coalesce(least(greatest((p_patch ->> 'progress_pct')::int, 0), 100), g.progress_pct),
    health_pct = case when p_patch ? 'health_pct' then least(greatest((p_patch ->> 'health_pct')::int, 0), 100) else g.health_pct end,
    branch = coalesce(left(p_patch ->> 'branch', 120), g.branch),
    pr_number = coalesce((p_patch ->> 'pr_number')::int, g.pr_number),
    head_sha = coalesce(p_patch ->> 'head_sha', g.head_sha),
    review = coalesce(p_patch -> 'review', g.review),
    merged_at = case when p_patch ? 'merged' and (p_patch ->> 'merged')::boolean then now() else g.merged_at end,
    updated_at = now()
  where g.id = v_id
  returning g.* into r;
  if not found then raise exception 'GOAL_NOT_FOUND'; end if;
  return to_jsonb(r);
end $$;

create or replace function public.bot_agent_goals_list(p_status text default null, p_limit int default 20)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(g) order by g.updated_at desc), '[]'::jsonb)
  from (select * from public.agent_goals where p_status is null or status = p_status
        order by updated_at desc limit least(greatest(p_limit, 1), 100)) g
$$;

-- ---------- memory ----------

create or replace function public.bot_agent_mem_add(p_kind text, p_body text, p_tags text[] default '{}', p_importance int default 3, p_pinned boolean default false)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_body text := btrim(left(p_body, 1500));
begin
  if char_length(v_body) < 3 then raise exception 'EMPTY_MEMORY'; end if;
  select id into v_id from public.agent_memory where lower(body) = lower(v_body) limit 1;
  if v_id is not null then
    update public.agent_memory set importance = least(importance + 1, 5), last_used_at = now(),
           pinned = pinned or coalesce(p_pinned, false) where id = v_id;
    return v_id;
  end if;
  insert into public.agent_memory(kind, body, tags, importance, pinned)
  values (coalesce(nullif(p_kind, ''), 'fact'), v_body, coalesce(p_tags, '{}'),
          least(greatest(coalesce(p_importance, 3), 1), 5), coalesce(p_pinned, false))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.bot_agent_mem_search(p_query text, p_limit int default 8)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_out jsonb; v_ids bigint[];
begin
  with hits as (
    select m.id, m.kind, m.body, m.tags, m.importance, m.pinned, m.created_at,
           ts_rank(m.fts, websearch_to_tsquery('simple', p_query)) * (1 + m.importance * 0.25) as score
    from public.agent_memory m
    where btrim(coalesce(p_query, '')) <> '' and m.fts @@ websearch_to_tsquery('simple', p_query)
    order by score desc, m.created_at desc
    limit least(greatest(p_limit, 1), 30)
  )
  select coalesce(jsonb_agg(to_jsonb(h) - 'score' order by h.score desc), '[]'::jsonb), coalesce(array_agg(h.id), '{}')
    into v_out, v_ids from hits h;
  update public.agent_memory set last_used_at = now() where id = any(v_ids);
  return v_out;
end $$;

create or replace function public.bot_agent_mem_core(p_limit int default 40)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(m) - 'fts' order by m.importance desc, m.created_at desc), '[]'::jsonb)
  from (select id, kind, body, tags, importance, pinned, created_at from public.agent_memory
        where pinned or importance >= 5 order by pinned desc, importance desc, created_at desc
        limit least(greatest(p_limit, 1), 100)) m
$$;

create or replace function public.bot_agent_mem_old(p_older_than_days int, p_limit int default 80)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
  from (select id, kind, body, importance, created_at from public.agent_memory
        where not pinned and importance <= 3 and created_at < now() - make_interval(days => greatest(p_older_than_days, 1))
        order by created_at limit least(greatest(p_limit, 1), 200)) m
$$;

create or replace function public.bot_agent_mem_replace(p_ids bigint[], p_kind text, p_body text, p_importance int default 4)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.agent_memory(kind, body, importance, pinned)
  values (coalesce(nullif(p_kind, ''), 'lesson'), left(p_body, 1500), least(greatest(p_importance, 1), 5), false)
  returning id into v_id;
  delete from public.agent_memory where id = any(coalesce(p_ids, '{}')) and id <> v_id;
  return v_id;
end $$;

create or replace function public.bot_agent_mem_forget(p_id bigint)
returns boolean language sql security definer set search_path = '' as $$
  with d as (delete from public.agent_memory where id = p_id returning 1) select exists(select 1 from d)
$$;

create or replace function public.bot_agent_mem_count()
returns int language sql stable security definer set search_path = '' as $$ select count(*)::int from public.agent_memory $$;

-- ---------- inbox ----------

create or replace function public.bot_agent_inbox_add(p_tg_user_id bigint, p_username text, p_is_admin boolean, p_body text, p_tg_message_id bigint default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.agent_inbox(tg_user_id, username, is_admin, body, tg_message_id)
  values (p_tg_user_id, left(p_username, 64), coalesce(p_is_admin, false), left(p_body, 2000), p_tg_message_id)
  returning id into v_id;
  delete from public.agent_inbox where handled and created_at < now() - interval '60 days';
  return v_id;
end $$;

create or replace function public.bot_agent_inbox_take(p_limit int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_out jsonb;
begin
  with taken as (
    update public.agent_inbox i set handled = true
     where i.id in (select id from public.agent_inbox where not handled order by created_at limit least(greatest(p_limit, 1), 100) for update skip locked)
    returning i.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'user', t.tg_user_id, 'username', t.username,
                                               'is_admin', t.is_admin, 'text', t.body, 'at', t.created_at) order by t.created_at), '[]'::jsonb)
    into v_out from taken t;
  return v_out;
end $$;

-- ---------- journal ----------

create or replace function public.bot_agent_journal_add(p_kind text, p_body text, p_data jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into public.agent_journal(kind, body, data) values (p_kind, left(p_body, 4000), coalesce(p_data, '{}'::jsonb)) returning id into v_id;
  delete from public.agent_journal where created_at < now() - interval '60 days';
  return v_id;
end $$;

create or replace function public.bot_agent_journal_recent(p_limit int default 10, p_kind text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'body', j.body, 'at', j.created_at) order by j.created_at desc), '[]'::jsonb)
  from (select * from public.agent_journal where p_kind is null or kind = p_kind order by created_at desc limit least(greatest(p_limit, 1), 50)) j
$$;

-- ---------- ACL: service_role only ----------

revoke all on function public.bot_agent_state_get() from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_state_patch(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_claim(text,int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_goal_save(bigint,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_goals_list(text,int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_add(text,text,text[],int,boolean) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_search(text,int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_core(int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_old(int,int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_replace(bigint[],text,text,int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_forget(bigint) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_mem_count() from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_inbox_add(bigint,text,boolean,text,bigint) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_inbox_take(int) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_journal_add(text,text,jsonb) from public, anon, authenticated, service_role;
revoke all on function public.bot_agent_journal_recent(int,text) from public, anon, authenticated, service_role;

grant execute on function public.bot_agent_state_get() to service_role;
grant execute on function public.bot_agent_state_patch(jsonb) to service_role;
grant execute on function public.bot_agent_claim(text,int) to service_role;
grant execute on function public.bot_agent_goal_save(bigint,jsonb) to service_role;
grant execute on function public.bot_agent_goals_list(text,int) to service_role;
grant execute on function public.bot_agent_mem_add(text,text,text[],int,boolean) to service_role;
grant execute on function public.bot_agent_mem_search(text,int) to service_role;
grant execute on function public.bot_agent_mem_core(int) to service_role;
grant execute on function public.bot_agent_mem_old(int,int) to service_role;
grant execute on function public.bot_agent_mem_replace(bigint[],text,text,int) to service_role;
grant execute on function public.bot_agent_mem_forget(bigint) to service_role;
grant execute on function public.bot_agent_mem_count() to service_role;
grant execute on function public.bot_agent_inbox_add(bigint,text,boolean,text,bigint) to service_role;
grant execute on function public.bot_agent_inbox_take(int) to service_role;
grant execute on function public.bot_agent_journal_add(text,text,jsonb) to service_role;
grant execute on function public.bot_agent_journal_recent(int,text) to service_role;
