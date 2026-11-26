from aiogram import types
from utils.validation import Validation
from db.rpc import bot_get_user_status


async def _answer_by_code(message: types.Message, question: str, private: bool):
    tg_id = message.from_user.id
    ok, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI")
    if not ok:
        Validation.log_warning("_answer_by_code", tg_id, "_answer_by_code", error)
        await message.answer("❌ Неверный Telegram ID")
        return
    kind = navigator.fast_kind(question)