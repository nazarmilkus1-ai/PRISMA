-- Fix the permission helper used by authenticated RLS / Realtime policies.
-- Identity is derived from the server-issued PRISMA auth email, never from editable user metadata.

create or replace function private.has_permission(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with identity as (
    select nullif(auth.jwt() ->> 'email', '') as email
  ), parsed as (
    select substring(email from '^tg-([0-9]+)@admins\.prisma\.internal$') as tg
    from identity
  )
  select exists (
    select 1
    from public.users u
    join public.admins a on a.user_id = u.id
    join public.role_permissions rp on rp.role_id = a.role_id
    join public.permissions p on p.id = rp.permission_id
    where u.telegram_id = (select tg::bigint from parsed where tg is not null)
      and p.key = p_permission_key
  );
$$;
