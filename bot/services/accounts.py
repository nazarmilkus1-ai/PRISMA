def forget(tg_id: int | None = None) -> None:
    if tg_id is None:
        return
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in accounts.forget: %s", tg_id)
        return
    _alias_cache.pop(tg_id, None)

async def primary_for(tg_id: int, now: float | None = None) -> int | None:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in accounts.primary_for: %s", tg_id)
        return None
    # ... rest of function