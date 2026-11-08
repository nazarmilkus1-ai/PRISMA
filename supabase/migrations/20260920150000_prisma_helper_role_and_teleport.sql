-- PRISMA staff: add HELPER role and teleport permissions.
-- Idempotent so production state can be reconciled safely.

INSERT INTO public.roles (name, description, priority)
VALUES ('helper', 'Хелпер', 30)
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description,
    priority = EXCLUDED.priority;

INSERT INTO public.permissions ("key", description, category) VALUES
  ('teleport.self', 'Телепортация хелпера', 'teleport'),
  ('teleport.to_player', 'Телепортация к игроку', 'teleport'),
  ('teleport.to_here', 'Телепортация игрока к себе', 'teleport'),
  ('teleport.accept', 'Принятие запросов на телепортацию', 'teleport')
ON CONFLICT ("key") DO UPDATE
SET description = EXCLUDED.description,
    category = EXCLUDED.category;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p
  ON p."key" IN (
    'player.view',
    'application.view',
    'report.view',
    'report.assign',
    'teleport.self',
    'teleport.to_player',
    'teleport.to_here',
    'teleport.accept'
  )
WHERE r.name = 'helper'
ON CONFLICT (role_id, permission_id) DO NOTHING;
