-- PRISMA_AI long memory: a rolling summary of everything older than the recent-messages window.
-- Bot-only data (service_role). RLS is on with no policies.
create table if not exists public.ai_chat_summary (
  telegram_id bigint not null,
  chat_id bigint not null,
  summary text not null check (char_length(summary) <= 2000),
  updated_at timestamptz not null default now(),
  primary key (telegram_id, chat_id)
);
alter table public.ai_chat_summary enable row level security;
revoke all on table public.ai_chat_summary from public, anon, authenticated;

create or replace function public.bot_ai_summary_get(p_tg_id bigint, p_chat_id bigint)
returns text language sql security definer set search_path to ''
as $function$
  select s.summary from public.ai_chat_summary s
   where s.telegram_id = p_tg_id and s.chat_id = p_chat_id
     and s.updated_at > now() - interval '90 days';
$function$;

-- An empty summary clears it (used by /forget). Old summaries of everyone are cleaned on the way.
create or replace function public.bot_ai_summary_set(p_tg_id bigint, p_chat_id bigint, p_summary text)
returns void language plpgsql security definer set search_path to ''
as $function$
begin
  if coalesce(btrim(p_summary), '') = '' then
    delete from public.ai_chat_summary where telegram_id = p_tg_id and chat_id = p_chat_id;
  else
    insert into public.ai_chat_summary(telegram_id, chat_id, summary, updated_at)
    values (p_tg_id, p_chat_id, left(p_summary, 2000), now())
    on conflict (telegram_id, chat_id) do update set summary = excluded.summary, updated_at = now();
  end if;
  delete from public.ai_chat_summary where updated_at < now() - interval '90 days';
end;
$function$;

revoke all on function public.bot_ai_summary_get(bigint,bigint) from public, anon, authenticated;
grant execute on function public.bot_ai_summary_get(bigint,bigint) to service_role;
revoke all on function public.bot_ai_summary_set(bigint,bigint,text) from public, anon, authenticated;
grant execute on function public.bot_ai_summary_set(bigint,bigint,text) to service_role;
