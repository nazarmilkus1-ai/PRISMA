from utils.validation import Validation

# ... existing code ...

async def _allowed(tg_id: int) -> bool:
    ok, _ = Validation.validate_telegram_id(tg_id, "Telegram ID в _allowed")
    if not ok:
        logger.warning("Invalid Telegram ID in _allowed: %s", tg_id)
        return False
    # ... rest of function