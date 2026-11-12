import asyncio
import logging
import os
import socket
import uuid

from aiohttp import web
from aiogram import Bot, Dispatcher, F, Router
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.fsm.storage.redis import RedisStorage
from redis.asyncio import Redis
import sentry_sdk

from config import BOT_TOKEN, ADMIN_GROUP_ID, MODERATION_GROUP_ID, REDIS_URL, LOG_LEVEL, PRISMA_ENV
from handlers import (
    start, application, profile, link, moderation, reports, polls, clans, menu, news, errors,
    player, admin, admin_panel, quick, reminders, automod, chat_commands, social, market, minecraft_commands, support,
    help as help_, admin_actions, rules, guide, ai,
)
from services.notifications import run_notification_worker
from services.minecraft_bridge import MinecraftChatBridge
from services.onboarding import run_onboarding_reminder_worker
from services.briefing import run_briefing_worker
from services.community_membership import run_community_membership_worker
from utils.commands import PUBLIC_COMMANDS, set_group_commands
from middlewares import TelegramActivityMiddleware
from utils.mode import configure_mode_store
from utils.module_runtime import attach_module_dispatch_gate, attach_module_gate

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
from services.ai.diagnostics import install as install_error_buffer
install_error_buffer()

logging.getLogger("aiogram.event").setLevel(logging.WARNING)

SENTRY_DSN = os.getenv("SENTRY_DSN", "").strip()
if SENTRY_DSN:
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        environment=PRISMA_ENV,
        traces_sample_rate=0.0,
        send_default_pii=False,
    )


async def health(request):
    return web.json_response({"service": "prisma-bot", "status": "ok"})


async def start_health_server():
    app = web.Application()
    app.router.add_get("/", health)
    app.router.add_get("/health", health)
    app.router.add_get("/api/health", health)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", int(os.getenv("PORT", "10000")))
    await site.start()
    return runner


async def make_storage():
    if REDIS_URL.startswith("redis://") or REDIS_URL.startswith("rediss://"):
        try:
            redis = Redis.from_url(
                REDIS_URL,
                decode_responses=True,
                max_connections=4,
                health_check_interval=30,
            )
            await redis.ping()
            return RedisStorage(redis=redis), redis
        except Exception as exc:
            # Redis is optional for bot availability. FSM can safely fall back
            # to process memory while Redis is exhausted/unavailable.
            logging.error(
                "Redis unavailable (%s); falling back to MemoryStorage. "
                "Bot will remain available, but FSM state is not persistent across restarts.",
                exc,
            )
            return MemoryStorage(), None
    return MemoryStorage(), None


POLLING_LOCK_KEY = os.getenv("TELEGRAM_POLLING_LOCK_KEY", "prisma:telegram:polling-lock").strip()
POLLING_LOCK_TTL = max(30, int(os.getenv("TELEGRAM_POLLING_LOCK_TTL", "90")))
POLLING_LOCK_REFRESH = max(10, min(POLLING_LOCK_TTL // 3, 30))


async def acquire_polling_lock(redis: Redis):
    if redis is None:
        logging.warning("Telegram polling lock unavailable because Redis is not connected")
        return None, None

    owner = f"{socket.gethostname()}:{os.getpid()}:{uuid.uuid4().hex}"
    while True:
        acquired = await redis.set(POLLING_LOCK_KEY, owner, nx=True, ex=POLLING_LOCK_TTL)
        if acquired:
            break

        current_owner = await redis.get(POLLING_LOCK_KEY)
        logging.warning(
            "Telegram polling lock is currently owned by %s; waiting for the "
            "active instance to finish or release the lock before starting polling.",
            current_owner or "unknown owner",
        )
        # Render can start the replacement instance before terminating the old
        # one during a rolling deploy. Waiting here keeps the replacement healthy
        # while guaranteeing that only one process ever polls Telegram.
        await asyncio.sleep(5)

    stop_refresh = asyncio.Event()

    async def refresh_lock():
        script = """
        if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('expire', KEYS[1], ARGV[2])
        end
        return 0
        """
        while not stop_refresh.is_set():
            try:
                await asyncio.wait_for(stop_refresh.wait(), timeout=POLLING_LOCK_REFRESH)
                break
            except asyncio.TimeoutError:
                renewed = await redis.eval(script, 1, POLLING_LOCK_KEY, owner, POLLING_LOCK_TTL)
                if renewed != 1:
                    raise RuntimeError("Telegram polling lock was lost while the bot was running")

    refresh_task = asyncio.create_task(refresh_lock())

    async def release_lock():
        stop_refresh.set()
        refresh_task.cancel()
        try:
            await refresh_task
        except asyncio.CancelledError:
            pass
        script = """
        if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('del', KEYS[1])
        end
        return 0
        """
        try:
            await redis.eval(script, 1, POLLING_LOCK_KEY, owner)
        except Exception:
            logging.exception("Failed to release Telegram polling lock")

    logging.info("Telegram polling lock acquired by %s", owner)
    return owner, release_lock


async def verify_moderation_group(bot: Bot):
    if not MODERATION_GROUP_ID:
        logging.warning("MODERATION_GROUP_ID is not configured")
        return False
    try:
        chat = await bot.get_chat(MODERATION_GROUP_ID)
        me = await bot.get_me()
        member = await bot.get_chat_member(chat.id, me.id)
        status = getattr(member, "status", "")
        if status not in {"administrator", "creator"}:
            logging.error("Moderation group found, but bot is not an administrator: %s", chat.title)
            return False

        missing = []
        for attr in ("can_delete_messages", "can_restrict_members", "can_invite_users"):
            if hasattr(member, attr) and not getattr(member, attr):
                missing.append(attr)
        if missing:
            logging.warning("Bot permissions missing in %s: %s", chat.title, ", ".join(missing))

        logging.info(
            "Moderation group connected: %s (%s), bot_status=%s",
            chat.title,
            chat.id,
            status,
        )
        return True
    except Exception as exc:
        logging.error("Moderation group unavailable: %s", exc)
        return False


async def main():
    # Bind the HTTP health endpoint before Telegram API calls so Render can detect the service port during startup.
    health_server = await start_health_server()
    bot = Bot(BOT_TOKEN)
    await bot.set_my_commands(PUBLIC_COMMANDS)
    await set_group_commands(bot)

    storage, redis = await make_storage()
    await configure_mode_store(redis)
    dp = Dispatcher(storage=storage)
    dp.message.middleware(TelegramActivityMiddleware())
    minecraft_chat_bridge = MinecraftChatBridge()
    dp.message.outer_middleware(minecraft_chat_bridge)
    dp.callback_query.outer_middleware(quick.QuickUsageMiddleware())

    # Feature-specific routers are gated independently; mixed player handlers
    # are intentionally not gated as a whole.
    for module_router, module_id in (
        (application.router, "applications"),
        (profile.router, "players"),
        (reports.router, "reports"),
        (polls.router, "voting"),
        (clans.router, "clans"),
        (news.router, "public-content"),
        (social.router, "social"),
        (market.router, "market"),
        (minecraft_commands.router, "minecraft"),
        (moderation.router, "moderation"),
        (automod.router, "moderation"),
    ):
        attach_module_gate(module_router, module_id)

    # These routers intentionally combine multiple feature areas. Dispatch-level
    # gates keep unrelated core/help handlers available while enforcing the
    # registry toggle for each recognized command and callback.
    attach_module_dispatch_gate(
        player.router,
        command_modules={
            "me": "players",
            "stats": "analytics",
            "achievements": "players",
            "warnings": "moderation",
            "server": "minecraft",
            "battle": "battles",
            "battles": "battles",
            "events": "events",
            "notifications": "notifications",
            "my_reports": "reports",
            "top": "players",
            "appeal": "appeals",
            "my_appeals": "appeals",
        },
        callback_modules={
            "profile": "players",
            "player:stats": "analytics",
            "player:achievements": "players",
            "player:punishments": "moderation",
            "player:server": "minecraft",
            "player:battles": "battles",
            "player:events": "events",
            "event:reg:*": "events",
            "event:unreg:*": "events",
            "player:notifications": "notifications",
            "notify:*": "notifications",
            "player:reports": "reports",
            "player:top": "players",
            "appeal:*": "appeals",
            "player:appeals": "appeals",
            "player:clan": "clans",
        },
    )
    attach_module_dispatch_gate(
        chat_commands.router,
        command_modules={
            "onboarding": "applications",
            "warn": "moderation",
            "варн": "moderation",
            "пред": "moderation",
            "предупреждение": "moderation",
            "mute": "moderation",
            "мут": "moderation",
            "заткнуть": "moderation",
            "ban": "moderation",
            "бан": "moderation",
            "чс": "moderation",
            "kick": "moderation",
            "кик": "moderation",
            "unmute": "moderation",
            "размут": "moderation",
            "говори": "moderation",
            "unban": "moderation",
            "разбан": "moderation",
            "вернуть": "moderation",
            "unwarn": "moderation",
            "снятьварн": "moderation",
            "снять_варн": "moderation",
            "варны": "moderation",
            "warns": "moderation",
            "муты": "moderation",
            "mutes": "moderation",
            "топ": "players",
            "top": "players",
            "ники": "players",
            "nicks": "players",
            "nicknames": "players",
            "стата": "analytics",
            "stats": "analytics",
            "неактив": "analytics",
            "кто_неактив": "analytics",
            "кто": "players",
            "who": "players",
            "inactive": "analytics",
            "кланы": "clans",
            "clans": "clans",
            "мойклан": "clans",
            "мой_клан": "clans",
            "клан": "clans",
            "clan": "clans",
            "браки": "social",
            "marriages": "social",
            "брак": "social",
            "marriage": "social",
            "обнять": "social",
            "пожать": "social",
            "датьпять": "social",
            "поддержать": "social",
            "чат": "chat",
            "chat": "chat",
            "население": "analytics",
            "population": "analytics",
            "кто_онлайн": "analytics",
            "online": "analytics",
            "актив": "analytics",
            "active": "analytics",
            "модер": "moderation",
            "модерка": "moderation",
            "повысить": "moderation",
            "promote": "moderation",
            "понизить": "moderation",
            "demote": "moderation",
            "снять": "moderation",
            "разжаловать": "moderation",
        },
        callback_modules={},
        text_patterns=(
            (r"^/(?:кто|who)(?:@\w+)?\s+неактив(?:\s+\d+)?$", "analytics"),
            (r"^/(?:кто|who)(?:@\w+)?\s+админ(?:ы)?$", "moderation"),
            (r"^/(?:кто|who)(?:@\w+)?\s+(?:я\??|ты(?:\s+.+)?)$", "players"),
            (r"^кто\s+неактив(?:\s+\d+)?$", "analytics"),
            (r"^кто\s+админ(?:ы)?$", "moderation"),
            (r"^кто\s+(?:я\??|ты(?:\s+.+)?)$", "players"),
            (r"^кланы$", "clans"),
            (r"^клан\s+.+$", "clans"),
            (r"^браки$", "social"),
            (r"^стат(?:а|истика)$", "analytics"),
            (r"^ники$", "players"),
            (r"^топ(?:\s+.+)?$", "players"),
            (r"^[+-]чат$", "chat"),
            (r"^актив(?:\s+\d+)?$", "analytics"),
        ),
    )

    # Staff callbacks are still feature entrypoints: hiding participant pages
    # alone must not leave admin mutation handlers active when a module is off.
    for staff_router in (admin.router, admin_actions.router):
        attach_module_dispatch_gate(
            staff_router,
            command_modules={
                "app_approve": "applications",
                "app_reject": "applications",
                "report_status": "reports",
                "appeal_review": "appeals",
                "appeal_approve": "appeals",
                "appeal_reject": "appeals",
                "players": "players",
            },
            callback_modules={
                "adm:app:*": "applications",
                "adm:rep:*": "reports",
                "adm:apl:*": "appeals",
                "admin:applications": "applications",
                "admin:reports": "reports",
                "admin:appeals": "appeals",
                "admin:automod": "moderation",
                "admin:moderation": "moderation",
                "admin:server": "minecraft",
                "admin:players": "players",
            },
        )

    dp.include_router(rules.router)
    dp.include_router(guide.router)
    private = Router(name="private_context")
    private.message.filter(F.chat.type == "private")
    private.callback_query.filter(F.message.chat.type == "private")

    for r in (
        start.router, application.router, profile.router, link.router, moderation.router,
        reports.router, polls.router, clans.router, news.router, help_.router, ai.router, quick.router, reminders.router, player.router,
        admin_panel.router, admin.router,
        admin_actions.router,
        # Social and market callbacks are private UI callbacks; they must be
        # registered before menu's catch-all stale_callback.
        social.router, market.router, minecraft_commands.router, support.router, menu.router, ai.free_router, errors.router,
    ):
        private.include_router(r)

    dp.include_router(private)
    dp.include_router(ai.group_router)
    # Group social commands are intentionally handled by chat_commands; keep
    # legacy group handlers after the dedicated social router.
    dp.include_router(chat_commands.router)
    dp.include_router(automod.router)

    await verify_moderation_group(bot)

    worker_stop = asyncio.Event()
    notification_task = asyncio.create_task(run_notification_worker(bot, worker_stop))
    onboarding_task = asyncio.create_task(run_onboarding_reminder_worker(bot, worker_stop))
    briefing_task = asyncio.create_task(run_briefing_worker(bot, worker_stop))

    community_membership_task = asyncio.create_task(
        run_community_membership_worker(bot, worker_stop)
    )
    minecraft_chat_bridge_task = asyncio.create_task(
        minecraft_chat_bridge.run(bot, worker_stop)
    )

    if ADMIN_GROUP_ID:
        try:
            chat = await bot.get_chat(ADMIN_GROUP_ID)
            logging.info("Admin notification group connected: %s", chat.title)
        except Exception as exc:
            logging.warning("Admin notification group unavailable: %s", exc)

    polling_lock_owner = None
    release_polling_lock = None
    try:
        polling_lock_owner, release_polling_lock = await acquire_polling_lock(redis)
        logging.info("Prisma bot started")
        await dp.start_polling(bot)
    finally:
        worker_stop.set()
        notification_task.cancel()
        onboarding_task.cancel()
        briefing_task.cancel()
        community_membership_task.cancel()
        minecraft_chat_bridge_task.cancel()
        if release_polling_lock:
            await release_polling_lock()
        await health_server.cleanup()
        if redis:
            await redis.aclose()
        await bot.session.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception:
        if SENTRY_DSN:
            sentry_sdk.capture_exception()
            sentry_sdk.flush(timeout=2)
        raise
