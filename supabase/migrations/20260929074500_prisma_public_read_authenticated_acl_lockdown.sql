-- PRISMA 2.0.0: public read gateways are intentionally callable by anon only.
-- Authenticated participants already have their own scoped gateways and do not need
-- a second SECURITY DEFINER execution path for public reads.

revoke execute on function public.get_public_awards(integer) from authenticated;
revoke execute on function public.get_public_clans(integer) from authenticated;
revoke execute on function public.get_public_event_details(text) from authenticated;
revoke execute on function public.get_public_events(integer) from authenticated;
revoke execute on function public.get_public_map_data() from authenticated;
revoke execute on function public.get_public_media(integer) from authenticated;
revoke execute on function public.get_public_news(integer) from authenticated;
revoke execute on function public.get_public_polls(integer) from authenticated;
revoke execute on function public.get_public_seasons(integer) from authenticated;
revoke execute on function public.get_public_server_status() from authenticated;
revoke execute on function public.get_public_wiki(text, integer) from authenticated;

grant execute on function public.get_public_awards(integer) to anon;
grant execute on function public.get_public_clans(integer) to anon;
grant execute on function public.get_public_event_details(text) to anon;
grant execute on function public.get_public_events(integer) to anon;
grant execute on function public.get_public_map_data() to anon;
grant execute on function public.get_public_media(integer) to anon;
grant execute on function public.get_public_news(integer) to anon;
grant execute on function public.get_public_polls(integer) to anon;
grant execute on function public.get_public_seasons(integer) to anon;
grant execute on function public.get_public_server_status() to anon;
grant execute on function public.get_public_wiki(text, integer) to anon;