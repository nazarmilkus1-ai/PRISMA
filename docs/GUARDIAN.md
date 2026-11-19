# Охранник (агент B)

Окремий від бота наглядач. Живёт в панели на Vercel (`/admin/api/guardian/tick`), запускается GitHub Actions каждые 10 минут (`.github/workflows/guardian.yml`). Не зависит от Render, поэтому видит, когда бот лёг, и может его перезапустить.

## Что делает сам (безопасное)
- Проверяет `BOT_HEALTH_URL` (по умолчанию `https://prisma-a8qt.onrender.com/health`) и доступность Supabase.
- Если бот не отвечает ≥ `GUARDIAN_DOWN_MINUTES` (10) — перезапускает сервис на Render. Кулдаун `GUARDIAN_RESTART_COOLDOWN_MIN` (30 мин), не больше `GUARDIAN_RESTART_DAILY_CAP` (3) в сутки.
- Шлёт алерты в Telegram (через `BOT_TOKEN`, работает даже когда polling-бот мёртв) — в `GUARDIAN_ALERT_CHAT_ID`/`ADMIN_GROUP_ID`, тема `GUARDIAN_ALERT_THREAD_ID`.
- Видит упавший деплой Render и создаёт предложение.

## Что делает только по кнопке
Всё остальное — предложения в `/admin/dashboard/guardian` (право `ops.manage`: owner, head_admin): redeploy/rollback Render. Код, env и БД он сам не меняет.

## Переменные Vercel
| Имя | Нужна для |
|---|---|
| `GUARDIAN_SECRET` (≥16 симв.) | авторизация tick; тот же в GitHub secret |
| `RENDER_API_KEY`, `RENDER_SERVICE_ID` | рестарт/деплой/статус (без них — только алерты) |
| `GUARDIAN_ALERT_THREAD_ID` | тема для алертов (опц.) |

GitHub secrets: `GUARDIAN_URL` (например `https://prisma-minecraft.vercel.app`), `GUARDIAN_SECRET`.

## Самовыключение
Охранник вне Render и вне бота, поэтому рестарт/деплой Render его не отключает. Бот-агент (A) не может менять Vercel/GitHub-часть охранника без подтверждения.

## Данные
`guardian_events`, `guardian_state`, `guardian_proposals` — только через RPC (`guardian_*` для service_role, `staff_guardian_*` для панели).
