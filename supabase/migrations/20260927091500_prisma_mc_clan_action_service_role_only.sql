revoke execute on function public.mc_clan_action(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mc_clan_action(uuid, text, text) to service_role;