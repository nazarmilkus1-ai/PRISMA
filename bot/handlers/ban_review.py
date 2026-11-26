from aiogram import F, Router, types
from aiogram.filters import Command

from utils.validation import Validation
from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment
from services import ban_review
from utils.errors import safe_rpc_error
from utils.permissions import is_admin_mode

router = Router(name="ban_review")


@router.callback_query(F.data.startswith(f"{ban_review.CB_PREFIX}:"))
async def on_decision(call: types.CallbackQuery):
    parsed = ban_review.parse_callback(call.data or "")
    if parsed is None:
        await call.answer("Кнопка устарела.", show_alert=True)
        return
    action, tg_id = parsed
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для действия")
    if not valid:
        Validation.log_warning("on_decision", tg_id, "on_decision", error)
        await call.answer("Некорректный Telegram ID.", show_alert=True)
        return
    admin_id = call.from_user.id
    if action == "ok":
        result = await bot_lift_punishment(tg_id, "BAN", admin_id)
    else:
        result = await bot_ban_review_keep(tg_id, admin_id)
    if result.error:
        await call.answer(safe_rpc_error(result, "Не удалось выполнить действие."), show_alert=True)
        return
    who = f"@{call.from_user.username}" if call.from_user.username else call.from_user.full_name
    if action == "ok":
        status = await ban_review.invite_back(call.bot, tg_id)
        note = f"✅ Возвращение подтвердил {who}: {status}"
    else:
        note = f"⛔ Бан оставил {who}. Снять его можно командой /unban."
    try:
        base = call.message.html_text if call.message else ""
        await call.message.edit_text(f"{base}\n\n{note}", parse_mode="HTML", reply_markup=None)
    except Exception:
        pass
    await call.answer("Готово.")