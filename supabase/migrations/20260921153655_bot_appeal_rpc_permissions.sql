-- Restrict the bot-only appeal RPC to the server-side Supabase role.
revoke execute on function public.bot_create_appeal(bigint, text, uuid) from public, anon, authenticated;
grant execute on function public.bot_create_appeal(bigint, text, uuid) to service_role;
