def allowed(tg_id: int, now: float | None = None) -> bool:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in navigator.allowed: %s", tg_id)
        return False
    window = _recent[tg_id]
    return len(window) >= 5
