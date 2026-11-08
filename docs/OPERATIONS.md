# Operations

## Deployment topology

The repository describes a split deployment model:

- Vercel serves the participant site at the root and the staff dashboard under /admin.
- Render runs the Telegram bot as a persistent Python process using long polling and background workers.
- The Minecraft plugin runs inside a compatible Paper server.
- Supabase provides PostgreSQL, Auth, RLS, RPC gateways, and shared domain state.
- Redis provides persistent bot FSM storage when REDIS_URL is configured.

These are deployment patterns, not preconfigured services included with the source code. A self-hosted operator must configure their own provider projects, credentials, domains, and server.

## Database operations

1. Confirm the target Supabase project reference.
2. Inspect the remote migration history and pending migrations.
3. Back up an existing database before applying changes.
4. Review RLS policies, RPC grants, and role permissions after migrations.
5. Use forward migrations for schema changes. Do not rewrite migrations that may have been applied.

The checked-in supabase/config.toml is a partial fragment. Generate a full Supabase CLI configuration and merge the repository-specific function settings before using CLI workflows.

## Health checks

The website and dashboard expose GET /api/health. A 200 response indicates required configuration is present; 503 indicates the process is not ready. Health checks do not prove that every integration is functioning.

## Bot operations

The bot uses Telegram long polling. Run only one active polling process for a given bot token unless the runtime has been explicitly designed for safe multi-instance operation. Production should configure Redis for persistent FSM state and monitor background notification/onboarding workers.

## Minecraft operations

The plugin targets Paper 26.3 and Java 25. Keep the plugin's runtime config outside Git. Back up the plugin data directory, including player homes, spawn points, journey data, graves, and mode settings. Test upgrades and restore procedures on a separate server before production.

## Release procedure

1. Confirm the exact release commit and version.
2. Run release and architecture verification.
3. Build/typecheck site and panel, compile the bot, and build the plugin with Java 25.
4. Apply migrations to an isolated test database and verify RLS/RPC.
5. Run end-to-end tests using test accounts and a test Paper server.
6. Verify monitoring, backups, health checks, and rollback steps.
7. Deploy components in a coordinated order and record the deployed commit.

Do not treat skipped CI jobs as successful checks. Do not deploy an integration candidate to production solely because source files are present.

## Rollback

- Website/dashboard: redeploy the last known-good build; do not assume the database can be rolled back with the application.
- Bot: stop the new process and restore the previous compatible build and environment.
- Plugin: stop Paper, restore the previous JAR, and restart. Preserve plugin data directories.
- Database: prefer a corrective forward migration. Restore from backup only after assessing data loss and operational impact.

## Incident response

Rotate exposed credentials, preserve sanitized logs, identify the affected commit and deployment, and document follow-up actions. Never post secrets or player data in public issues.
