# Getting Started

This guide describes a cautious local setup for the PRISMA 2.1.0 integration candidate. PRISMA is a connected system; running one component alone does not create a complete installation.

## Prerequisites

| Requirement | Purpose |
| --- | --- |
| Git | Source control |
| Node.js 24.x + npm | Participant site and staff dashboard |
| Python 3.12.10 | Telegram bot baseline |
| Java 25 | Current Paper plugin build target |
| Docker (optional) | Local Redis service |
| Supabase project | PostgreSQL, Auth, RLS, RPC, migrations |
| Telegram bot | Bot API access |
| Redis-compatible endpoint | Persistent bot FSM state in production |
| Paper 26.3 test server | Current plugin API target |

You also need hosting for the site/dashboard and a persistent-process host for the Telegram bot.

## 1. Clone

```powershell
git clone https://github.com/nazarmilkus1-ai/PRISMA.git
cd PRISMA
```

## 2. Prepare Supabase first

All runtime components depend on one PRISMA Supabase project. Before applying migrations, identify the target database and take a backup if it is not empty.

The migration chain begins with:
- 20260807235959_rename_legacy_tables.sql: renames existing public.users and public.applications tables to users_legacy_v0 and applications_legacy_v0 when they exist.
- 20260808000000_init.sql: creates the initial PRISMA schema.
- 20260808000001_backfill_legacy_data.sql: copies the legacy pair when both tables exist; on a clean database it skips the backfill.

The rename changes object names and can affect dependent views, functions, or external integrations. Do not run the migration chain against an existing database without reviewing dependencies and creating a backup.

The checked-in supabase/config.toml is a partial configuration fragment, not a complete Supabase CLI project configuration. Generate a full configuration with supabase init and merge the repository-specific function settings into it. Do not replace a full config with the fragment.

After the project and configuration are ready, a typical CLI workflow is:

```powershell
supabase login
supabase link --project-ref <YOUR_PROJECT_REF>
supabase migration list
supabase db push
```

Do not run these commands blindly against production. Confirm the linked project reference and pending migration list first.

## 3. Run Redis locally

The root docker-compose.yml defines Redis only; it does not start the complete PRISMA stack.

```powershell
docker compose up -d redis
```

Do not expose Redis publicly without suitable authentication and network restrictions.

## 4. Configure and run the Telegram bot

```powershell
Copy-Item bot/.env.example bot/.env
# Edit bot/.env with your own values.

Push-Location bot
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python main.py
Pop-Location
```

Set BOT_TOKEN, SUPABASE_URL, and SUPABASE_SERVICE_ROLE_KEY. For production, configure REDIS_URL with redis:// or rediss://. In-memory FSM storage is for local smoke tests only.

## 5. Run the participant website

```powershell
Copy-Item site/.env.example site/.env.local
# Edit site/.env.local.

Push-Location site
npm install
npm run dev
Pop-Location
```

The local URL is normally http://localhost:3000.

## 6. Run the staff dashboard

```powershell
Copy-Item panel/.env.example panel/.env.local
# Edit panel/.env.local.

Push-Location panel
npm install
npm run dev -- --port 3001
Pop-Location
```

The dashboard uses the /admin base path. When running independently on port 3001, open http://localhost:3001/admin.

## 7. Build the Paper plugin

The current build targets Paper API 26.3.build.195-stable and Java 25.

```powershell
Push-Location minecraft-plugin
.\gradlew.bat clean build
Pop-Location
```

The JAR is written to minecraft-plugin/build/libs. On a test Paper server, stop the server, copy the generated JAR into plugins, create plugins/PrismaPlugin/config.yml from config.yml.example, set the server-only Supabase URL and service-role key, initialize Geyser/Floodgate if needed, and test before production.

Never commit the real plugin config.yml.

## 8. End-to-end validation

Use test accounts and an isolated environment: complete a Telegram application, approve it through the staff workflow, confirm backend identity linkage, validate site sign-in, test Java and Bedrock joins, check staff permissions/audit, verify notifications and chat bridge, then restart the server and validate persistence.

Do not test moderation commands against real community players during initial setup.

## Related guides

- [Configuration](CONFIGURATION.md)
- [Architecture](ARCHITECTURE.md)
- [Operations](OPERATIONS.md)
- [Minecraft authentication](MINECRAFT_AUTH.md)
- [Release status](RELEASE_STATUS.md)
