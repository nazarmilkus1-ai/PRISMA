-- Reliable 5-minute trigger for the guardian tick (GitHub cron is throttled and unreliable).
-- The shared secret lives in Supabase Vault under the name 'guardian_secret' (never in git).
create extension if not exists pg_net with schema extensions;

create or replace function private.guardian_ping()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  select ds.decrypted_secret into v_secret
  from vault.decrypted_secrets ds
  where ds.name = 'guardian_secret'
  limit 1;

  if v_secret is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://prisma-minecraft.vercel.app/admin/api/guardian/tick',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function private.guardian_ping() from public, anon, authenticated, service_role;

select cron.schedule('prisma-guardian-tick', '*/5 * * * *', 'select private.guardian_ping()');
