-- Notes of one kind (e.g. the agent's ideas) for the admin «Идеи» view.
create or replace function public.bot_agent_mem_list(p_kind text, p_limit int default 8)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'importance', m.importance) order by m.importance desc, m.created_at desc), '[]'::jsonb)
  from (select id, body, importance, created_at from public.agent_memory
        where kind = p_kind order by importance desc, created_at desc
        limit least(greatest(p_limit, 1), 20)) m
$$;
revoke all on function public.bot_agent_mem_list(text, int) from public, anon, authenticated, service_role;
grant execute on function public.bot_agent_mem_list(text, int) to service_role;
