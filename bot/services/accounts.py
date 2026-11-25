async def primary_for(tg_id: int, now: float | None = None) -> int | None:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in accounts.primary_for: %s", tg_id)
        return None
    # ... rest of function