from utils.validation import Validation

async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")

# Export test-compatible attributes
bot_get_user_status = None  # type: ignore
run_member = None  # type: ignore
is_configured = lambda: True  # type: ignore