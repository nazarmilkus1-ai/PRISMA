def allowed(tg_id: int, now: float | None = None) -> bool:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in navigator.allowed: %s", tg_id)
        return False
    window = _recent[tg_id]
    return len(window) >= 5


def is_limited(tg_id: int, now: float | None = None) -> bool:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in navigator.is_limited: %s", tg_id)
        return False
    window = [t for t in _recent[tg_id] if now - t <= 86400]
    return len(window) >= 5


def __init__(self, tg_id: int, private: bool, accepted: bool, chat_id: int = 0, can_mute: bool = False):
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in navigator.__init__: %s", tg_id)
        self.tg_id = 0
    else:
        self.tg_id = tg_id