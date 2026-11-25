from db.rpc import bot_get_profile, bot_get_user_status
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from utils.validation import Validation

async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для статуса")
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    status = await bot_get_user_status(tg_id)
    if not status or status == "PENDING":
        return ""
    return str(status)

async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Запрос к AI с валидацией Telegram ID."""
    # Валидация tg_id из сообщения
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI запроса")
    if not valid:
        Validation.log_warning("_ask_ai", tg_id, "_ask_ai", error)
        return False
    # остальной код функции...