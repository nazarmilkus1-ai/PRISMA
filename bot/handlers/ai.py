from aiogram import Router
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator
from services.ai.member_tools import run_member

router = Router(name="ai")


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    valid, error = Validation.validate_telegram_id(tg_id, "_status_for_intent")
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")