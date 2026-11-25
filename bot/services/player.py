# ... existing code ...
ok, _ = Validation.validate_telegram_id(tg_id)
if not ok:
    logger.warning("Invalid Telegram ID in player: %s", tg_id)
    return
# rest of function