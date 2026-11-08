# PRISMA deployment

PRISMA v2 uses a split deployment model:

- Vercel: public participant/community site at `/`.
- Vercel: admin panel at `/admin`. The route is reachable over HTTP, but the application requires authentication and staff authorization.
- Render: Telegram bot as the long-running Python process (`python main.py`).

## Vercel routing

The root `vercel.json` owns the two Vercel services. The `site` catch-all rewrite is intentionally last so `/admin/*` reaches the panel service first.

The Telegram bot is not proxied through Vercel. Telegram traffic goes directly to the Render bot service, and the bot uses long polling.

## Render bot runtime

Canonical Render service settings:

- Service: `prisma`
- Runtime: Python
- Root directory: `bot`
- Build command: `pip install -r requirements.txt`
- Start command: `python main.py`
- Health check: `/health`
- Redis: optional, used for persistent FSM storage when `REDIS_URL` is configured.
- Notification worker: long-running in-process worker.
- Onboarding worker: long-running in-process worker.

The bot keeps polling Telegram from Render and does not require webhook or Vercel Cron infrastructure.

## Environment contract

Required bot variables:

- `BOT_TOKEN`
- `SUPABASE_URL`
- `SUPABASE_KEY`

Recommended production variables:

- `REDIS_URL`
- `PRISMA_ENV=production`
- `PANEL_URL`
- `OWNER_TG_ID`
- `ADMIN_GROUP_ID`
- `MODERATION_GROUP_ID`

Secrets belong in Render environment variables; never commit real values.

## Branch note

The development branch for PRISMA v2 is `rebuild/prisma-v3`. The existing Render service currently tracks `main-old`; change that Render Dashboard setting before promoting this branch to that live service. Do not create a second bot service while the existing bot is running, because two polling instances would compete for the same Telegram update stream.
