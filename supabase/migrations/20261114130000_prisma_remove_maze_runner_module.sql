-- The Maze Runner mode was dropped before 2.1.0 (the server is a plain survival server).
-- The plugin controller, its command and its module registry entry are removed; this removes the stored switch.
delete from public.prisma_module_states where module_id = 'minecraft-maze-runner';
