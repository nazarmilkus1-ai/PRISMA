-- PRISMA 2.0.0: public read gateways are intentionally callable by anon,
-- but authenticated clients do not need a second execution path.
-- Keep the public web contract while reducing authenticated EXECUTE surface.

revoke execute on function public.get_public_event_details(text) from authenticated;
revoke execute on function public.get_public_map_data() from authenticated;
revoke execute on function public.get_public_polls(integer) from authenticated;
revoke execute on function public.get_public_server_status() from authenticated;

grant execute on function public.get_public_event_details(text) to anon;
grant execute on function public.get_public_map_data() to anon;
grant execute on function public.get_public_polls(integer) to anon;
grant execute on function public.get_public_server_status() to anon;
