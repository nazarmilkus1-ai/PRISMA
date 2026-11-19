# PRISMA 2.1.0 — Release Status

**Status: integration candidate. Not a stable release declaration.**

The inspected integration snapshot reports VERSION=2.1.0. Component package manifests and the Minecraft command catalog are aligned to 2.1.0. The Paper plugin build targets Paper API 26.3.build.195-stable and Java 25.

## Scope of the release

PRISMA 2.1.0 ships for a plain survival server. Maze Runner, the market and the Escape-From/wipe ideas are out of scope and were removed. Added since the first candidate: PRISMA Points (`/pp`, game menu shop and selling, event entry fees and prize payout), Minecraft encyclopedia in the Wiki, panel Wiki editor through the `staff_manage_wiki` gateway, `/menu` chest GUI (Java and Bedrock), personal fog-of-war `/worldmap`, Bedrock gamertags with spaces, one extra account per player on the other platform (never online at the same time), graves that last 15 minutes, and the weekly inactivity warning (off until `ACTIVITY_WARN=1`): under 60 min in Minecraft or under 50 messages in the Telegram chat per 7 days = 1 warning (30 days, 5 active warnings = ban). Bans last 30 days; when the term ends the player stays banned until an admin presses «Вернуть» (the bot then unbans him in the chat and sends an invite link) or «Оставить бан»; `/bans` lists those waiting.

## Verification state

- Production branch: PRISMA, commit fd193ece3196b9c485945bf49999f9188b788fd7, checked on 2026-11-14.
- GitHub Actions on that branch (architecture, bot, site, panel, minecraft-plugin) passed. The plugin job is a compile check only.
- Production migrations are applied through 20261115100000, plus 20261115120000 (event fees), 20261115190000 (staff_manage_wiki), 20261115210400 (wiki search limit) and 20261115220000 (wiki 2.1 refresh). Pending: the Minecraft encyclopedia seeds 20261115210000–210300 (about 450 KB; apply with `supabase db push`; one article is already in).
- Secrets: render.env, vercel.env and plugin config.yml were briefly tracked (ba7e7d8) and remain in git history of a public repository; every key in them must be rotated before release.
- Live Paper 26.3 runtime validation (menu, map, multi-account block, graves, Floodgate `replace-spaces`) was not confirmed yet.

These are point-in-time observations. Re-check the exact commit before making a release statement.

## Release gate

Do not mark 2.1.0 stable until all of the following have been completed against the exact release candidate:

1. Run release, architecture, RPC-contract, and module-registry checks.
2. Run Python compilation and website/dashboard typecheck and build checks.
3. Build the plugin using Java 25 and the checked-in Gradle 9.4.0 wrapper.
4. Verify JAR contents and plugin metadata.
5. Apply and validate migrations on an isolated test database.
6. Test Java and Bedrock identity flows on an isolated Paper 26.3 environment with the intended Geyser/Floodgate setup.
7. Test persistence and recovery for homes, spawns, journeys/checkpoints, graves, and chat-bridge queues across restarts and failure cases.
8. Test permission boundaries, moderation actions, and audit records for staff roles below, equal to, and above a target role.
9. Complete a Telegram application → staff approval → backend eligibility → Minecraft join/authentication flow.
10. Verify health checks, deployment configuration, backups, and rollback procedures.

Update this page when verification state changes. Remove candidate warnings only after the corresponding checks have passed.
