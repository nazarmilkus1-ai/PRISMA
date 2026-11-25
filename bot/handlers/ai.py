from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.member_tools import peek_draft, publish, run_member, take_draft

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
