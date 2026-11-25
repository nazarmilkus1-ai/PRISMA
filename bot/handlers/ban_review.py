from aiogram import F, Router, types
from aiogram.filters import Command

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
    result = await bot_lift_punishment(tg_id, "BAN", admin_id)
    if result.error:
        await call.answer("❌ Ошибка при снятии бана.", show_alert=True)
        return
    chat = await bot_get_community_chat_id()
    chat_id = chat.data if not chat.error and isinstance(chat.data, int) else None
    link = None
    try:
        await call.bot.unban_chat_member(chat_id, tg_id, only_if_banned=True)
    except Exception:
        logger.exception("unban in community chat failed for %s", tg_id)
    try:
        created = await call.bot.create_chat_invite_link(
            chat_id, name="return after ban", member_limit=1, expire_date=int(time.time()) + 7 * 24 * 3600
        )
        link = created.invite_link
    except Exception:
        logger.exception("invite link failed for %s", tg_id)
    text = "✅ Бан успешно снят."
    text += f"\nВот ссылка для входа в чат (действует 7 дней, один вход):\n{link}" if link else "\nЗайдите обратно в чат сообщества."
    await call.bot.send_message(tg_id, text, disable_web_page_preview=True)
    await call.answer("✅ Бан снят.", show_alert=True)
    await call.message.edit_text("Бан успешно снят.")