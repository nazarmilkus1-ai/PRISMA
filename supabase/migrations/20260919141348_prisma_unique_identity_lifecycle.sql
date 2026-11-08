-- Canonical uniqueness rules for active Minecraft identities and active clan owners.
ALTER TABLE public.clans DROP CONSTRAINT IF EXISTS clans_owner_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS clans_active_owner_unique
  ON public.clans(owner_id)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_minecraft_nickname_ci_unique
  ON public.users(lower(trim(minecraft_nickname)))
  WHERE minecraft_nickname IS NOT NULL AND deleted_at IS NULL;
