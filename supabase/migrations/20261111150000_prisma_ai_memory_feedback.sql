-- PRISMA_AI: persistent short chat memory and 👍/👎 feedback on answers.
-- Bot-only data (service_role). RLS is on with no policies, so anon/authenticated can't read it.
create table if not exists public.ai_chat_log (
  id bigserial primary key,
  telegram_id bigint not null,
  chat_id bigint not null,
  role text not null check (role in ('user','assistant')),
  content text not null check (char_length(content) <= 2000),
  answer_id text,
  agent boolean not null default false,
  rating smallint check (rating in (-1,1)),
  rated_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists ai_chat_log_recent_idx on public.ai_chat_log (telegram_id, chat_id, created_at desc);
create unique index if not exists ai_chat_log_answer_idx on public.ai_chat_log (answer_id) where answer_id is not null;
alter table public.ai_chat_log enable row level security;
revoke all on table public.ai_chat_log from public, anon, authenticated;

create or replace function public.bot_ai_log_message(
  p_tg_id bigint, p_chat_id bigint, p_role text, p_content text, p_answer_id text default null, p_agent boolean default false
) returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if p_role not in ('user','assistant') or coalesce(p_content,'') = '' then return; end if;
  insert into public.ai_chat_log(telegram_id, chat_id, role, content, answer_id, agent)
  values (p_tg_id, p_chat_id, p_role, left(p_content, 2000), p_answer_id, coalesce(p_agent,false))
  on conflict do nothing;
  -- retention: 30 days, and at most 200 rows per user and chat
  delete from public.ai_chat_log
   where telegram_id = p_tg_id and chat_id = p_chat_id
     and (created_at < now() - interval '30 days'
          or id not in (select l.id from public.ai_chat_log l
                         where l.telegram_id = p_tg_id and l.chat_id = p_chat_id
                         order by l.created_at desc, l.id desc limit 200));
end; $function$;

create or replace function public.bot_ai_recent(p_tg_id bigint, p_chat_id bigint, p_limit int default 16)
returns jsonb language sql security definer set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'role', r.role, 'content', r.content, 'answer_id', r.answer_id, 'rating', r.rating,
           'ts', extract(epoch from r.created_at)) order by r.created_at, r.id), '[]'::jsonb)
  from (select * from public.ai_chat_log
         where telegram_id = p_tg_id and chat_id = p_chat_id
           and created_at > now() - interval '7 days'
         order by created_at desc, id desc limit least(greatest(coalesce(p_limit,16),1),40)) r;
$function$;

-- Only the person the answer was written for can rate it. Returns false if it isn't theirs / not found.
create or replace function public.bot_ai_rate(p_tg_id bigint, p_answer_id text, p_rating int)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare n int;
begin
  if p_rating not in (-1,1) then return false; end if;
  update public.ai_chat_log set rating = p_rating, rated_at = now()
   where answer_id = p_answer_id and telegram_id = p_tg_id and role = 'assistant';
  get diagnostics n = row_count;
  return n > 0;
end; $function$;

create or replace function public.bot_ai_feedback_stats(p_days int default 7)
returns jsonb language sql security definer set search_path to ''
as $function$
  select jsonb_build_object(
    'days', p_days,
    'answers', count(*) filter (where role = 'assistant' and answer_id is not null),
    'up', count(*) filter (where rating = 1),
    'down', count(*) filter (where rating = -1),
    'agent_up', count(*) filter (where rating = 1 and agent),
    'agent_down', count(*) filter (where rating = -1 and agent))
  from public.ai_chat_log where created_at > now() - make_interval(days => greatest(coalesce(p_days,7),1));
$function$;

revoke all on function public.bot_ai_log_message(bigint,bigint,text,text,text,boolean) from public, anon, authenticated;
revoke all on function public.bot_ai_recent(bigint,bigint,int) from public, anon, authenticated;
revoke all on function public.bot_ai_rate(bigint,text,int) from public, anon, authenticated;
revoke all on function public.bot_ai_feedback_stats(int) from public, anon, authenticated;
grant execute on function public.bot_ai_log_message(bigint,bigint,text,text,text,boolean) to service_role;
grant execute on function public.bot_ai_recent(bigint,bigint,int) to service_role;
grant execute on function public.bot_ai_rate(bigint,text,int) to service_role;
grant execute on function public.bot_ai_feedback_stats(int) to service_role;
