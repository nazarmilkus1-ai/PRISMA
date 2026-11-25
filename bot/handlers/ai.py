from aiogram import Router
import asyncio
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator
from services.ai.member_tools import run_member

router = Router(name="ai")

ai_memory = type("AI_Memory", (), {
    "hydrate": asyncio.coroutine(lambda self: None)(),
    "persist": asyncio.coroutine(lambda self: None)(),
})()

navigator_obj = navigator
def is_configured() -> bool:
    return True

free_router = Router(name="ai_free")


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    valid, error = Validation.validate_telegram_id(tg_id, "_status_for_intent")
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")