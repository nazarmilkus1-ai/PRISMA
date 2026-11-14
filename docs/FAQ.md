# FAQ

## Is PRISMA 2.1.0 stable?

The inspected source baseline is an integration candidate, not a stable release declaration. Check docs/RELEASE_STATUS.md for the verification state and release gate.

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
