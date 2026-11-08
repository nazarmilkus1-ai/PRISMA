# Configuration

PRISMA uses separate environment files for each runtime. The .env.example files contain safe placeholders, not production configurations.

## General rules

- Never commit .env, .env.local, a real Minecraft config.yml, or provider exports.
- Keep service-role keys on trusted server runtimes only.
- Do not prefix secrets with NEXT_PUBLIC_.
- Store production secrets in Vercel, Render, or the relevant host's secret manager.
- Rotate credentials that may have appeared in Git history, logs, screenshots, or messages.
- Use separate test credentials and databases for development.

## Telegram bot — bot/.env

Required: BOT_TOKEN, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

Optional/common settings include REDIS_URL, OWNER_TG_ID, ADMIN_GROUP_ID, MODERATION_GROUP_ID, SITE_URL, PANEL_URL, Minecraft server address/port variables, SENTRY_DSN, LOG_LEVEL, and PRISMA_ENV. Check bot/.env.example for the current list.

Use a Redis protocol URL (redis:// or rediss://). An HTTPS REST endpoint is not interchangeable with REDIS_URL. In-memory FSM storage is for local tests only.

## Participant website — site/.env.local

The baseline example includes NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, SUPABASE_SERVICE_ROLE_KEY, NEXT_PUBLIC_BOT_USERNAME, NEXT_PUBLIC_DYNMAP_URL, NEXT_PUBLIC_SITE_URL, and optional Sentry DSNs.

The service-role key is server-side only. Never expose it through a browser bundle.

## Staff dashboard — panel/.env.local

The baseline example includes NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (or the documented legacy anon-key alias), SUPABASE_SERVICE_ROLE_KEY, NEXT_PUBLIC_BOT_USERNAME, NEXT_PUBLIC_SITE_URL, ADMIN_TELEGRAM_IDS, ADMIN_EMAILS, NOTIFY_FUNCTION_SECRET, and optional Sentry DSNs.

Grant staff access only to intended accounts. Review both application-level RBAC and database RLS/RPC grants.

## Paper plugin — runtime config.yml

Create the server file from minecraft-plugin/src/main/resources/config.yml.example. Required values are supabase.url and supabase.service-role-key. This key belongs only on the trusted Minecraft server.

## Local copies

```powershell
Copy-Item bot/.env.example bot/.env
Copy-Item site/.env.example site/.env.local
Copy-Item panel/.env.example panel/.env.local
```

For the plugin, copy the example to the Paper server's plugins/PrismaPlugin/config.yml, not into the source tree as a real configuration.

## Configuration validation

Before starting a service, check required variables against its example, confirm the Supabase project URL, keep server-only secrets out of browser bundles, verify Redis protocol URLs, and confirm Telegram IDs and bot permissions.
