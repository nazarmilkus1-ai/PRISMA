# PRISMA 2.1.0 — Release Status

**Status: integration candidate. Not a stable release declaration.**

The inspected integration snapshot reports VERSION=2.1.0. Component package manifests and the Minecraft command catalog are aligned to 2.1.0. The Paper plugin build targets Paper API 26.3.build.195-stable and Java 25.

## Verification state at publication preparation

- Inspected integration branch: integration/2.1.0-bot-site.
- Inspected integration commit: 7b81c30f6bab34892501c80fd477ae6c58f4bc7c.
- No GitHub Actions workflow run was returned for that branch or commit when checked on 2026-11-08.
- Live Paper 26.3 runtime validation was not confirmed.

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
