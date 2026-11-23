-- Does an admin have an unread message for the agent? Used to wake it up while it waits for merge decisions.
create or replace function public.bot_agent_inbox_peek()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.agent_inbox where not handled and is_admin)
$$;
revoke all on function public.bot_agent_inbox_peek() from public, anon, authenticated, service_role;
grant execute on function public.bot_agent_inbox_peek() to service_role;
