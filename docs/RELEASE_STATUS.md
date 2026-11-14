# PRISMA 2.1.0 — Release Status

**Status: integration candidate. Not a stable release declaration.**

The inspected integration snapshot reports VERSION=2.1.0. Component package manifests and the Minecraft command catalog are aligned to 2.1.0. The Paper plugin build targets Paper API 26.3.build.195-stable and Java 25.

## Scope of the release

PRISMA 2.1.0 ships for a plain survival server. Maze Runner, the market and the Escape-From/wipe ideas are out of scope and were removed. Added since the first candidate: `/menu` chest GUI (Java and Bedrock), personal fog-of-war `/worldmap`, Bedrock gamertags with spaces, one extra account per player on the other platform (never online at the same time), graves that last 15 minutes, and the weekly inactivity warning (off until `ACTIVITY_WARN=1`).

## Verification state

- Production branch: PRISMA, commit fd193ece3196b9c485945bf49999f9188b788fd7, checked on 2026-11-14.
- GitHub Actions on that branch (architecture, bot, site, panel, minecraft-plugin) passed. The plugin job is a compile check only.
- Production migrations are applied through 20261114180000.
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
