from aiogram import types
from utils.validation import Validation
from db.rpc import bot_get_user_status


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    ok, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI-цели")
    if not ok:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    return await bot_get_user_status(tg_id, kind)


async def run_member(tg_id: int, member_id: int) -> bool:
    ok, error = Validation.validate_telegram_id(tg_id, "Telegram ID для run_member")
    if not ok:
        Validation.log_warning("run_member", tg_id, "run_member", error)
        return False
    # Placeholder implementation - actual logic depends on context
    return True


def is_configured() -> bool:
    return True


async def _answer_by_code(message: types.Message, question: str, private: bool):
    tg_id = message.from_user.id
    ok, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI")
    if not ok:
        Validation.log_warning("_answer_by_code", tg_id, "_answer_by_code", error)
        await message.answer("❌ Неверный Telegram ID")
        return
    kind = navigator.fast_kind(question)