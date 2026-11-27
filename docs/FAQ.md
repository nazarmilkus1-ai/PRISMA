# FAQ

## Is PRISMA 2.1.0 stable?

The inspected source baseline is an integration candidate, not a stable release declaration. Check [RELEASE_STATUS.md](RELEASE_STATUS.md) for the verification state and release gate.

## Is this a one-click Minecraft server package?

No. PRISMA is an application ecosystem. You must provide Supabase, Telegram, hosting, Redis for persistent bot state in production, and a compatible Paper server.

## Which Paper/Java versions are targeted?

The 2.1.0 plugin build targets Paper API 26.3.build.195-stable and Java 25. Compatibility with other versions is not guaranteed.

## Does Bedrock work?

The plugin integrates with Geyser/Floodgate. Bedrock identity behavior must be tested with the actual server/proxy setup.

## Why does the bot need Redis?

Redis provides persistent FSM state when REDIS_URL is configured. In-memory storage is suitable only for local smoke tests; it is not durable across process restarts.

## Can I put the Supabase service-role key in the website environment?

Only as a server-side environment variable used by server-only code. Never expose it through NEXT_PUBLIC_ variables or browser bundles.

## Can I reuse the code because the repository is public?

The repository currently has no LICENSE file. Public visibility does not by itself grant general reuse or redistribution rights.

## Where can I find documentation about modules and their runtime management?

See [MODULES.md](MODULES.md) for the module registry, ownership model, runtime state in `public.prisma_module_states`, and the removal procedure. The admin dashboard at `/admin/dashboard/modules` (permission `modules.manage`) controls runtime enablement with audit logging.

## Where can I find documentation about the Guardian watchdog?

See [GUARDIAN.md](GUARDIAN.md) for the watchdog agent that monitors bot health, restarts Render services, and sends alerts.

## Where can I find documentation about Minecraft authentication?

See [MINECRAFT_AUTH.md](MINECRAFT_AUTH.md) for Java and Bedrock authentication flows, password management, and shared contracts.

## Where can I find the configuration reference?

See [CONFIGURATION.md](CONFIGURATION.md) for all environment variables for the bot, website, dashboard, and Minecraft plugin.

## Where can I find the architecture overview?

See [ARCHITECTURE.md](ARCHITECTURE.md) for component boundaries, data flow, security boundaries, and module lifecycle.

## Where can I find the development workflow?

See [DEVELOPMENT.md](DEVELOPMENT.md) for implementation order, module registry, database rules, and review checklist.

## Where can I find operations and deployment guidance?

See [OPERATIONS.md](OPERATIONS.md) for deployment topology, database operations, health checks, bot operations, Minecraft operations, release procedure, rollback, and incident response.