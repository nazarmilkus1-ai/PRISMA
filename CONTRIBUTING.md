# Contributing to PRISMA

Thank you for considering a contribution. PRISMA is a multi-component system, so changes must preserve the contracts and security boundaries shared by the bot, website, dashboard, plugin, and database.

## Before opening an issue

Search existing issues and documentation. For a bug report, include the affected component, expected and actual behavior, reproduction steps, relevant sanitized logs, and the version or commit tested.

Do not include access tokens, service-role keys, personal data, private server addresses, or production database exports.

## Development principles

1. Treat Supabase as the source of truth for shared domain data and privileged business operations.
2. Define shared RPC names, types, and enums in packages/contracts.
3. Make database changes through new forward migrations in supabase/migrations.
4. Keep Telegram, web, staff, and Minecraft UX in their respective consumers.
5. Enforce permissions on the server and database, not only in the UI.
6. Add verification for new architecture contracts and update modules/registry.json when ownership or dependencies change.
7. Do not rewrite historical migrations that may already have been applied.

## Validation

Run relevant checks before requesting review:

```powershell
node scripts/verify-release.mjs
node scripts/verify-architecture.mjs
node --test scripts/tests/verify-script-entrypoints.test.mjs
python -m compileall -q bot
```

For website or dashboard changes, also run npm run typecheck and npm run build in the affected app. For plugin changes, build with Java 25 using the checked-in Gradle wrapper and test on an isolated Paper 26.3 server.

A successful build does not replace end-to-end testing with a dedicated Supabase project, Telegram bot, Redis endpoint, and Paper test server.

## Pull requests

Keep each pull request focused. Describe the problem, implementation, migrations or configuration changes, security implications, validation performed, and rollback considerations. Mark unverified runtime behavior explicitly.

## License and contributions

The repository currently has no project license. Do not assume public visibility grants reuse rights or that submitting a pull request grants a specific copyright or patent license. The project owner must add a license and contribution terms before accepting external contributions under defined open-source terms.
