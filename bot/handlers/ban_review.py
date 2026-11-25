from aiogram import F, Router, types
from aiogram.filters import Command
from aiogram.methods import UnbanChatMember

from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment, bot_get_community_chat_id
from services import ban_review
from utils.errors import safe_rpc_error
from utils.permissions import is_admin_mode
from utils.validation import Validation
import logging

logger = logging.getLogger(__name__)

router = Router(name="ban_review")


@router.callback_query(F.data.startswith(f"{ban_review.CB_PREFIX}:"))
async def on_decision(call: types.CallbackQuery):
    parsed = ban_review.parse_callback(call.data or "")
    if parsed is None:
        await call.answer("Кнопка устарела.", show_alert=True)
        return
    action, tg_id = parsed
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для проверки доступа")
    if not valid:
        Validation.log_warning("on_decision", tg_id, "on_decision", error)
        await call.answer("❌ Неверный идентификатор пользователя.", show_alert=True)
        return
    admin_id = call.from_user.id
    valid2, error2 = Validation.validate_telegram_id(admin_id, "ID администратора")
    if not valid2:
        Validation.log_warning("on_decision", admin_id, "on_decision", error2)
        await call.answer("❌ Неверный идентификатор администратора.", show_alert=True)
        return

    if action == "ok":
        # Lift the ban
        result = await bot_lift_punishment(tg_id, "BAN", admin_id)
        if result and result.error is not None:
            await call.answer("❌ Ошибка при снятии бана.", show_alert=True)
            return
        # After lifting ban, proceed to unban in community chat
        chat = await bot_get_community_chat_id()
        if chat.error:
            await call.answer("❌ Не удалось получить ID чата.", show_alert=True)
            return
        chat_id = chat.data if isinstance(chat.data, int) else None
        if chat_id is None:
            await call.answer("❌ Не удалось получить ID чата.", show_alert=True)
            return
        # Unban the player in the community chat
        await call.bot.unban_chat_member(chat_id, tg_id, only_if_banned=True)
        # Notify the player about the unban
        await call.bot.send_message(tg_id, "Вы были разбанены в чате.")
        # Also send message to admin group about the unban
        await call.bot.send_message(admin_id, f"Игрок {tg_id} был разбанен в чате.")
    elif action == "keep":
        # Keep the ban - use bot_ban_review_keep
        await bot_ban_review_keep(tg_id, admin_id)
        await call.message.edit_text("Бан оставлен.", show_alert=True)
        return
    else:
        await call.answer("❌ Неизвестное действие.", show_alert=True)
        return