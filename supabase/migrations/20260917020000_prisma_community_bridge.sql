-- PRISMA community bridge.
-- Additive and idempotent: preserves legacy poll data while moving reads/writes
-- to normalized poll_options/poll_votes and exposes published news to the bot.

insert into public.poll_options (poll_id, text, position)
select p.id, trim(u.option_text), u.position
from public.polls p
cross join lateral unnest(coalesce(p.options, '{}'::text[])) with ordinality as u(option_text, position)
where not exists (
  select 1 from public.poll_options po where po.poll_id = p.id
);

insert into public.poll_votes (poll_id, option_id, user_id, created_at)
select pr.poll_id, po.id, pr.user_id, pr.created_at
from public.poll_ratings pr
join public.poll_options po
  on po.poll_id = pr.poll_id
 and po.position = coalesce(pr.option_index, -1) + 1
where pr.option_index is not null
  and not exists (
    select 1
    from public.poll_votes pv
    where pv.poll_id = pr.poll_id
      and pv.user_id = pr.user_id
      and pv.option_id = po.id
  );

update public.polls
set status = case when is_active then 'active' else 'finished' end
where coalesce(status, '') not in ('active', 'finished');

create or replace function public.bot_get_news(p_tg_id bigint default null)
returns json
language sql
security definer
set search_path = public
as $$
  select coalesce(
    json_agg(
      json_build_object(
        'id', n.id,
        'title', n.title,
        'body', n.body,
        'kind', n.kind,
        'published_at', n.published_at
      ) order by coalesce(n.published_at, n.created_at) desc
    ),
    '[]'::json
  )
  from (
    select id, title, body, kind, published_at, created_at
    from public.news
    where is_published = true
      and (published_at is null or published_at <= now())
    order by coalesce(published_at, created_at) desc
    limit 10
  ) n;
$$;

grant execute on function public.bot_get_news(bigint) to service_role;
revoke all on function public.bot_get_news(bigint) from public, anon, authenticated;

alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
revoke all on public.poll_options, public.poll_votes from anon, authenticated;
