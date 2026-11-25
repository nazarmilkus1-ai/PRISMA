from aiogram import BaseMiddleware, F, Router, types
from aiogram.filters import Command

from services import quick
from utils.permissions import get_application_status, is_admin_mode
from utils.validation import Validation

router = Router(name="quick")


class QuickUsageMiddleware(BaseMiddleware):
    """Counts taps on known sections; never blocks or alters the update."""

    async def __call__(self, handler, event, data):
        try:
            if isinstance(event, types.CallbackQuery) and event.from_user:
                callback_data = event.data
                if callback_data:  # игнорируем пустые callback data
                    quick.record(event.from_user.id, callback_data)
        except Exception:  # statistics must never break navigation
            pass
        return await handler(event, data)


async def _show(message: types.Message, tg_id: int):
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in _show: %s", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    await message.answer(quick.text(tg_id), parse_mode="HTML", reply_markup=quick.keyboard(tg_id))


@router.message(Command("quick", "fast", "q"))
async def quick_command(message: types.Message):
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in quick_command: %s", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    if await is_admin_mode(tg_id):
        from handlers.admin_panel import send_dashboard
        await send_dashboard(message)
        return
    if await get_application_status(tg_id) != "ACCEPTED":
        await message.answer("🔒 Быстрые действия открываются после одобрения заявки: /guide")
        return
    await _show(message, tg_id)


@router.callback_query(F.data == "quick")
async def quick_callback(callback: types.CallbackQuery):
    tg_id = callback.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in quick_callback: %s", error)
        await callback.answer("❌ Неверный идентификатор пользователя.", show_alert=True)
        return
    await callback.answer()
    await callback.message.answer(quick.text(tg_id), parse_mode="HTML",
                                  reply_markup=quick.keyboard(tg_id))