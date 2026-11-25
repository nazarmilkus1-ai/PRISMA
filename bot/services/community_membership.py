def _telegram_member(tg_id: int):
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in _telegram_member: %s", tg_id)
        return None
    # rest of function