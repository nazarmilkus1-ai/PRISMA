async def _stats(tg_id: int) -> str:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in _stats: %s", tg_id)
        return ""
    user, _ = await _user(tg_id)
    stats, err = await get_stats(tg_id)
    # ... rest of function