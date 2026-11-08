import logging
from html import escape

from aiogram import Router, types
from aiogram.types import ErrorEvent

from config import ADMIN_GROUP_ID

router = Router()
logger = logging.getLogger(__name__)


def _context(event: ErrorEvent) -> str:
    update = event.update
    user = None
    if getattr(update, "message", None):
        user = update.message.from_user
    elif getattr(update, "callback_query", None):
        user = update.callback_query.from_user
    if not user:
        return "Пользователь: неизвестен"
    name = f"@{user.username}" if user.username else user.full_name or "Пользователь"
    return f"Пользователь: {escape(name)} · TG <code>{user.id}</code>"


@router.error()
async def on_error(event: ErrorEvent):
    logger.exception("Unhandled Telegram update error", exc_info=event.exception)
    bot = event.bot
    if ADMIN_GROUP_ID:
        try:
            await bot.send_message(
                ADMIN_GROUP_ID,
                "🚨 <b>Внутренняя ошибка PRISMA</b>\n\n"
                f"{_context(event)}\n"
                f"Тип: <code>{escape(type(event.exception).__name__)}</code>\n"
                f"Ошибка: <code>{escape(str(event.exception))[:1500]}</code>",
                parse_mode="HTML",
            )
        except Exception:
            logger.exception("Failed to notify PRISMA admins about an error")
    update = event.update
    try:
        if getattr(update, "callback_query", None):
            await update.callback_query.answer(
                "❌ В PRISMA произошла внутренняя ошибка. Администраторы уже получили уведомление.",
                show_alert=True,
            )
        elif getattr(update, "message", None):
            await update.message.answer(
                "❌ В PRISMA произошла внутренняя ошибка. Администраторы уже получили уведомление."
            )
    except Exception:
        logger.exception("Failed to send safe user error")
    return True
