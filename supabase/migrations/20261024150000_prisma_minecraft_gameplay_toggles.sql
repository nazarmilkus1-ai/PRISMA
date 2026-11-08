-- PRISMA 2.1.0: runtime switches for individual Minecraft gameplay mechanics.
-- Forward-only migration. This file is committed to the repository only; do not apply to production without approval.
-- Default existing gameplay behavior is preserved: each new mechanic starts enabled.
insert into public.prisma_module_states(module_id, enabled)
values
  ('minecraft-teleport-requests', true),
  ('minecraft-homes', true),
  ('minecraft-spawns', true),
  ('minecraft-journey', true),
  ('minecraft-graves', true),
  ('minecraft-hud', true),
  ('minecraft-moderation', true),
  ('minecraft-tpall', true),
  ('minecraft-staff-teleport', true),
  ('minecraft-clan-commands', true),
  ('minecraft-village-commands', true),
  ('minecraft-village-protection', true),
  ('minecraft-chat-bridge', true),
  ('minecraft-maze-runner', false)
on conflict (module_id) do nothing;
