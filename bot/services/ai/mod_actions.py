target = int(payload["tg_id"])
ok, _ = Validation.validate_telegram_id(target)
if not ok:
    logger.warning("Invalid Telegram ID in mod_actions: %s", target)
    return
# rest of function