# Configuration

PRISMA uses separate environment files for each runtime. The .env.example files contain safe placeholders, not production configurations.

## General rules

- Never commit .env, .env.local, a real Minecraft config.yml, or provider exports.
- Keep service-role keys on trusted server runtimes only.
- Do not prefix secrets with NEXT_PUBLIC_.
- Store production secrets in Vercel, Render, or the relevant host's secret storage.
- Rotate credentials that may have appeared in Git history, logs, screenshots, or messages.
- Use separate test credentials and databases for development.

## Telegram bot — bot/.env

### Required
- `BOT_TOKEN` — Telegram bot token from @BotFather
- `SUPABASE_URL` — Supabase project URL (https://...)
- `SUPABASE_SERVICE_ROLE_KEY` — Supabase service role key (starts with `sb_secret_`)
  - Legacy alias `SUPABASE_KEY` is accepted for existing Render deployments

### Optional — Core
- `REDIS_URL` — Redis connection URL (redis:// or rediss:// protocol)
- `REDIS_TOKEN` — Redis token if required by provider
- `PRISMA_ENV` — Environment name (development, staging, production), default: development
- `LOG_LEVEL` — Logging level (DEBUG, INFO, WARNING, ERROR), default: INFO

### Optional — Plugin & Minecraft
- `PLUGIN_API_URL` — Minecraft plugin API endpoint URL
- `PLUGIN_API_KEY` — API key for plugin communication
- `MINECRAFT_HOST` — Minecraft server hostname
- `MINECRAFT_JAVA_ADDRESS` — Java edition server address (fallback: NEXT_PUBLIC_JAVA_ADDRESS)
- `MINECRAFT_BEDROCK_ADDRESS` — Bedrock edition server address (fallback: NEXT_PUBLIC_BEDROCK_ADDRESS)
- `MINECRAFT_JAVA_PORT` — Java edition RCON port, default: 25575
- `MINECRAFT_BEDROCK_PORT` — Bedrock edition RCON port, default: 18591 (fallback: NEXT_PUBLIC_BEDROCK_PORT)

### Optional — Telegram IDs & Groups
- `OWNER_TG_ID` — Telegram ID of the bot owner
- `ADMIN_GROUP_ID` — Telegram group ID for admin notifications
- `MODERATION_GROUP_ID` — Telegram group ID for moderation logs
- `ANNOUNCE_CHAT_ID` — Telegram chat ID for announcements

### Optional — External URLs
- `PANEL_URL` — Staff dashboard URL
- `SITE_URL` — Participant website URL (fallback: NEXT_PUBLIC_SITE_URL or default)

### Optional — Sentry & Web Server
- `SENTRY_DSN` — Sentry DSN for error tracking
- `PORT` — Web server port for health checks, default: 10000
- `TELEGRAM_POLLING_LOCK_KEY` — Redis key for polling lock, default: prisma:telegram:polling-lock
- `TELEGRAM_POLLING_LOCK_TTL` — Polling lock TTL in seconds, default: 90

### Optional — AI Features
- `AGENT_DM_COPILOT` — Enable AI copilot in DM (1/true/on/yes), default: disabled
- `AI_GROUP_PROACTIVE` — Enable proactive AI in groups (1/true/on/yes), default: enabled
- `AI_ADULT_CHATS` — Comma-separated list of chat IDs for adult content
- `AI_BENCH_MODELS` — Comma-separated list of models for benchmarking
- `AI_DIGEST` — Enable AI digest (1/true/on/yes), default: enabled
- `GITHUB_TOKEN` — GitHub token for diagnostics
- `GITHUB_REPO` — GitHub repository for diagnostics (owner/repo)

### Optional — Scheduled Tasks
- `BRIEFING_TZ` — Timezone for briefing, default: Europe/Kyiv
- `BRIEFING_HOUR` — Hour for briefing (0-23), default: 10
- `DIGEST_TZ` — Timezone for digest, default: Europe/Kyiv
- `DIGEST_HOUR` — Hour for digest (0-23), default: 20

Use a Redis protocol URL (redis:// or rediss://). An HTTPS REST endpoint is not interchangeable with REDIS_URL. In-memory FSM storage is for local tests only.

## Participant website — site/.env.local

### Required
- `NEXT_PUBLIC_SUPABASE_URL` — Supabase project URL (https://...)
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — Supabase publishable (anon) key
- `SUPABASE_SERVICE_ROLE_KEY` — Supabase service role key (server-side only)
- `NEXT_PUBLIC_BOT_USERNAME` — Telegram bot username (without @)
- `NEXT_PUBLIC_SITE_URL` — Website URL (https://...)

### Optional
- `NEXT_PUBLIC_DYNMAP_URL` — Dynmap URL for live map
- `SENTRY_DSN` — Sentry DSN for error tracking (client-side)
- `SENTRY_ORG` — Sentry organization slug
- `SENTRY_PROJECT` — Sentry project slug

The service-role key is server-side only. Never expose it through a browser bundle.

## Staff dashboard — panel/.env.local

### Required
- `NEXT_PUBLIC_SUPABASE_URL` — Supabase project URL (https://...)
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` — Supabase publishable (anon) key
- `SUPABASE_SERVICE_ROLE_KEY` — Supabase service role key (server-side only)
- `NEXT_PUBLIC_BOT_USERNAME` — Telegram bot username (without @)
- `NEXT_PUBLIC_SITE_URL` — Website URL (https://...)
- `ADMIN_TELEGRAM_IDS` — Comma-separated Telegram IDs of admins
- `ADMIN_EMAILS` — Comma-separated admin emails for auth
- `NOTIFY_FUNCTION_SECRET` — Secret for notify function verification

### Optional
- `SENTRY_DSN` — Sentry DSN for error tracking
- `SENTRY_ORG` — Sentry organization slug
- `SENTRY_PROJECT` — Sentry project slug

Grant staff access only to intended accounts. Review both application-level RBAC and database RLS/RPC grants.

## Paper plugin — runtime config.yml

Create the server file from `minecraft-plugin/src/main/resources/config.yml.example`. Required values:

### Required
- `supabase.url` — Supabase project URL (https://...)
- `supabase.service-role-key` — Supabase service role key (starts with `sb_secret_`)

### Optional — Server Connection
- `server.java-address` — Java edition server address
- `server.bedrock-address` — Bedrock edition server address
- `server.java-port` — Java edition RCON port, default: 25575
- `server.bedrock-port` — Bedrock edition RCON port, default: 18591
- `server.rcon-password` — RCON password

### Optional — Bot API
- `bot.api-url` — Bot API endpoint URL
- `bot.api-key` — API key for bot communication

### Optional — Features
- `features.chat-bridge` — Enable chat bridge between Telegram and Minecraft, default: true
- `features.player-stats` — Enable player stats tracking, default: true
- `features.moderation` — Enable moderation features, default: true
- `features.villages` — Enable village/clan system, default: true
- `features.graves` — Enable grave system, default: true
- `features.homes` — Enable player homes, default: true
- `features.journey` — Enable player journey, default: true
- `features.explore` — Enable explore map, default: true
- `features.spawn` — Enable spawn points, default: true
- `features.tpa` — Enable TPA (teleport requests), default: true

### Optional — Limits & Tuning
- `limits.max-homes` — Maximum homes per player, default: 5
- `limits.max-village-radius` — Maximum village radius, default: 100
- `limits.chat-bridge-cooldown` — Chat bridge cooldown in seconds, default: 2
- `tuning.cache-ttl` — Cache TTL in seconds, default: 300
- `tuning.metrics-interval` — Metrics collection interval in seconds, default: 60

This secret only on the trusted Minecraft server.

## Local copies

```powershell
Copy-Item bot/.env.example bot/.env
Copy-Item site/.env.example site/.env.local
Copy-Item panel/.env.example panel/.env.local
```

For the plugin, copy the example to the Paper server's plugins/PrismaPlugin/config.yml, not into the source tree as a real configuration.

## Configuration validation

Before starting a service, check required variables against its example, confirm the Supabase project URL, keep server-only secrets out of browser bundles, verify Redis protocol URLs, and confirm Telegram IDs and bot permissions.
