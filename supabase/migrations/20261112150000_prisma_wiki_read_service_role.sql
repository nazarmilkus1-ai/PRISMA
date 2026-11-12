-- The bot (service_role) reads the public wiki for PRISMA_AI; the ACL lockdown left only anon/authenticated.
grant execute on function public.get_public_wiki(text, integer) to service_role;
