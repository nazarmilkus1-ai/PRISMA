-- PRISMA: reset legacy implicit Minecraft bindings.
-- Older plugin versions automatically filled users.mojang_uuid on first login.
-- The new flow requires explicit Telegram /verify + Minecraft /prisma verify.
-- This migration is intentionally one-time and should not be rerun manually after
-- users begin completing the new explicit verification flow.

update public.users
set mojang_uuid = null,
    updated_at = now()
where mojang_uuid is not null;

delete from public.minecraft_link_codes
where used_at is null;
