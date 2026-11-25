from aiogram import F, Router, types
from aiogram.filters import Command

from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment
from services import ban_review
from utils.errors import safe_rpc_error
from utils.permissions import is_admin_mode
from utils.validation import Validation

router = Router(name="ban_review")


@router.callback_query(F.data.startswith(f"{ban_review.CB_PREFIX}:"))
async def on_decision(call: types.CallbackQuery):
    parsed = ban_review.parse_callback(call.data or "")
    if parsed is None:
        await call.answer("Кнопка устарела.", show_alert=True)
        return
    action, tg_id = parsed
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для разбана")
    if not valid:
        Validation.log_warning("on_decision", tg_id, "on_decision", error)
        await call.answer("❌ Неверный Telegram ID", show_alert=True)
        return
    admin_id = call.from_user.id