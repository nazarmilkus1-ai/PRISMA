# PRISMA

**A connected community platform for Minecraft servers.**

PRISMA coordinates player onboarding, community features, staff operations, and in-game server management through five connected components: a Telegram bot, participant website, staff dashboard, Paper plugin, and Supabase backend.

> **Release status — PRISMA 2.1.0 integration candidate.** This repository is being prepared for a clean public source release. The inspected integration snapshot had no GitHub Actions run recorded at the time of documentation preparation, and live Paper 26.3 runtime validation was not confirmed. Do not treat this status as a stable production release.

> **Self-hosting notice:** PRISMA is not a one-click hosted service. A complete deployment requires your own Supabase project, Telegram bot, hosting, secrets, Redis-compatible storage for persistent bot state, and a compatible Paper server.

## What is PRISMA?

PRISMA is a multi-component operations platform for a Minecraft community. Each component has a defined responsibility and shares one backend data model.

| Component | Responsibility |
| --- | --- |
| **Telegram bot** | Applications and onboarding, player interactions, notifications, community workflows, and bot-side moderation features |
| **Participant website** | Public community pages and the signed-in player experience |
| **Staff dashboard** | Staff tools for applications, players, moderation, reports, appeals, events, analytics, and administration |
| **Paper plugin** | In-game identity and whitelist integration, player commands, clans/villages, player utilities, moderation, and server events |
| **Supabase** | PostgreSQL, Supabase Auth, row-level security (RLS), RPC gateways, and schema migrations |

Shared TypeScript contracts and reusable UI components live in \`packages/\`. Domain ownership and module lifecycle metadata live in \`modules/registry.json\`.

## Capabilities

The following describes functionality present in the PRISMA 2.1.0 integration source. Presence in source code does not prove that a feature has passed a live-server test. See [Release Status](docs/RELEASE_STATUS.md) before enabling features in production.

### Player and community experience

- Telegram-based onboarding and membership application workflows.
- Player profiles, player directory, rankings, and statistics.
- Clans, membership roles, invitations, announcements, wars, and village/territory features.
- Player social relationships and community activity.
- Events, calendar views, news, Wiki, and public community information.
- Community market, polls, voting, and Player Battle experiences.
- Reports, support requests, appeals, and notifications.
- Minecraft server information, map/history surfaces, and a shared command reference.

### Staff and administration

- Application review and onboarding management.
- Player lookup and player-focused operational views.
- Role-based staff access, permission checks, and audit history.
- Moderation actions and punishment history.
- Reports and appeals workflows.
- Clan, event, market, news, and poll administration.
- Analytics, security/onboarding tools, and centrally managed module state.

### Minecraft 2.1.0 integration source

- Paper 26.3 plugin build target with Java 25.
- PRISMA player identity binding and whitelist eligibility checks.
- Java Edition PRISMA Auth (\`/register\`, \`/login\`, \`/changepass\`); Bedrock integration through Geyser/Floodgate.
- Clan/village commands and player-to-player teleport requests.
- Two personal home slots per player; main and named additional spawn points.
- Up to five personal checkpoints, private coordinate display, explicit coordinate sharing, and last-death information.
- Personal HUD/TAB information with online count, ping, and server TPS.
- Death-grave storage and recovery workflow, with a ten-minute recovery window in the current implementation.
- Staff teleportation, including confirmation-based \`/tpall\`.
- Server-side moderation commands and moderation history.
- A queued Minecraft ↔ Telegram chat bridge with identity checks, rate limits, and retry/lease handling.
- An optional, partial Maze Runner controller. It is not a complete implementation of all original map mechanics; see [Maze Runner notes](docs/MAZE_RUNNER.md).

## Architecture
                         ┌──────────────────────────┐
                         │         Supabase         │
                         │ PostgreSQL · Auth · RLS  │
                         │ RPC gateways · migrations│
                         └─────────────┬────────────┘
                                       │
                      shared contracts / domain rules
                                       │
          ┌─────────────────┬───────────────┼───────────────┬────────────────┐
          │                 │               │               │                │
     ┌────▼─────┐   ┌───────▼──────┐  ┌─────▼─────┐  ┌──────▼───────┐  ┌─────▼────┐
     │ Telegram │   │ Participant  │  │ Staff     │  │ Paper        │  │ Shared   │
     │ bot      │   │ website      │  │ dashboard │  │ plugin       │  │ packages │
     └──────────┘   └──────────────┘  └───────────┘  └──────────────┘  └──────────┘

The core rule is:

> **Supabase is the source of truth; shared contracts define component boundaries; consumers adapt those contracts to Telegram, web, staff, and Minecraft experiences.**

Privileged operations must be enforced by backend RPC/RLS/RBAC rules, not merely hidden in a browser UI or protected by a client-side check. See [Architecture](docs/ARCHITECTURE.md).

## Technology and compatibility

| Area | PRISMA 2.1.0 repository baseline |
| --- | --- |
| Website and dashboard | Next.js 16, React 19, TypeScript, Tailwind CSS 4 |
| Node.js | 24.x |
| Telegram bot | Python 3.12.10, aiogram 3.x |
| Bot state storage | Redis when \`REDIS_URL\` is configured; in-memory storage is for local testing only |
| Database and authentication | Supabase / PostgreSQL |
| Minecraft plugin | Java 25, Gradle 9.4.0, Paper API \`26.3.build.195-stable\` |

The plugin configuration targets Paper 26.3 and Java 25. This is a build target, not a guarantee of compatibility with other Paper versions or proxies. Validate the plugin on an isolated server before deploying it to a live community.

## Requirements

A complete self-hosted instance requires:

- Node.js 24.x and npm.
- Python 3.12.10 for the bot baseline.
- Java 25 for the current Minecraft plugin build.
- A Supabase project with the PRISMA migrations applied.
- A Telegram bot token and correctly configured community/staff chat IDs.
- A Redis-compatible endpoint for persistent bot FSM state in production.
- A Paper 26.3 server for the current plugin target.
- Hosting for the website/dashboard and a persistent process host for the bot.

The project does not include managed hosting, a production database, credentials, a preconfigured Telegram bot, or a Minecraft world/server.

## Quick start

Read [Getting Started](docs/GETTING_STARTED.md) and [Configuration](docs/CONFIGURATION.md) before connecting a real database, Telegram group, or Minecraft server.

### Clone

\`\`\`powershell
git clone https://github.com/nazarmilkus1-ai/PRISMA.git
cd PRISMA
\`\`\`

### Prepare Supabase

All components depend on the same PRISMA Supabase project. Review the migration chain and back up any existing database before applying it. The first migration renames existing \`public.users\` and \`public.applications\` tables to legacy names when they exist.

The checked-in \`supabase/config.toml\` is a **partial configuration fragment**, not a complete Supabase CLI project configuration. Generate a full configuration with \`supabase init\` and merge the required function settings rather than replacing a complete config with the fragment. See [Getting Started](docs/GETTING_STARTED.md).

### Run the Telegram bot

\`\`\`powershell
Copy-Item bot/.env.example bot/.env
# Edit bot/.env with your own values.

Push-Location bot
python -m venv .venv
.\\.venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
python main.py
Pop-Location
\`\`\`

For production, configure \`REDIS_URL\` with a Redis protocol URL (\`redis://\` or \`rediss://\`). An HTTPS REST URL is not a Redis connection URL.

### Run the participant website

\`\`\`powershell
Copy-Item site/.env.example site/.env.local
# Edit site/.env.local.

Push-Location site
npm install
npm run dev
Pop-Location
\`\`\`

The default local URL is normally \`http://localhost:3000\`.

### Run the staff dashboard

\`\`\`powershell
Copy-Item panel/.env.example panel/.env.local
# Edit panel/.env.local.

Push-Location panel
npm install
npm run dev -- --port 3001
Pop-Location
\`\`\`

The dashboard uses the \`/admin\` base path, so the local URL is normally \`http://localhost:3001/admin\` when using port \`3001\`.

### Build the Paper plugin

\`\`\`powershell
Push-Location minecraft-plugin
.\\gradlew.bat clean build
Pop-Location
\`\`\`

The distributable JAR is written to \`minecraft-plugin/build/libs/\`. Create the server's runtime \`plugins/PrismaPlugin/config.yml\` from [\`config.yml.example\`](minecraft-plugin/src/main/resources/config.yml.example). Never commit the real config file or service-role key.

## Documentation

| Guide | Contents |
| --- | --- |
| [Getting Started](docs/GETTING_STARTED.md) | Prerequisites, Supabase preparation, local start, and first-run sequence |
| [Configuration](docs/CONFIGURATION.md) | Environment variables and server-side secrets |
| [Architecture](docs/ARCHITECTURE.md) | Component responsibilities, contracts, backend boundaries, and modules |
| [Operations](docs/OPERATIONS.md) | Deployment model, migrations, health checks, backups, diagnostics, and rollback |
| [Minecraft authentication](docs/MINECRAFT_AUTH.md) | Java PRISMA Auth and Bedrock Geyser/Floodgate flow |
| [Maze Runner notes](docs/MAZE_RUNNER.md) | Current scope and limitations of the optional Maze Runner controller |
| [Development](docs/DEVELOPMENT.md) | Coding workflow, migrations, checks, and review requirements |
| [Release status](docs/RELEASE_STATUS.md) | What has and has not been verified for the 2.1.0 integration candidate |
| [FAQ](docs/FAQ.md) | Common deployment and compatibility questions |
| [Contributing](CONTRIBUTING.md) | How to propose a change or open a pull request |
| [Security](SECURITY.md) | Responsible vulnerability reporting |

## Verification

Run the baseline checks from the repository root:

\`\`\`powershell
node scripts/verify-release.mjs
node scripts/verify-architecture.mjs
node --test scripts/tests/verify-script-entrypoints.test.mjs
python -m compileall -q bot
\`\`\`

For the website and dashboard, run the commands from their respective directories:

\`\`\`powershell
npm install
npm run typecheck
npm run build
\`\`\`

For the Minecraft plugin on Java 25:

\`\`\`powershell
Push-Location minecraft-plugin
.\\gradlew.bat clean build
Pop-Location
\`\`\`

A successful compile or build does not replace an end-to-end test against a separately configured Supabase project, Telegram bot, Redis service, and Paper 26.3 test server. A skipped workflow job is not a successful test of that component.

## Security

- Never commit \`.env\`, \`.env.local\`, runtime \`config.yml\`, service-role keys, Telegram tokens, Redis credentials, private signing keys, database exports, or player data.
- \`SUPABASE_SERVICE_ROLE_KEY\` must remain server-side. Never expose it through a \`NEXT_PUBLIC_\` variable or browser bundle.
- Keep staff authorization in server-side code and Supabase RBAC/RLS/RPC checks.
- Treat credentials found in Git history, logs, screenshots, or public messages as exposed and rotate them.
- Use private vulnerability reporting where available; do not publish exploitable details in a public issue.

See [Security Policy](SECURITY.md).

## License

**No project license is currently included.** Public GitHub visibility does not automatically grant general permission to reuse, modify, or redistribute this code. The project owner must select and add a license before describing PRISMA as an open-source project.
