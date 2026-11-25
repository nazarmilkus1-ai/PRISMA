def __init__(self, tg_id: int, private: bool, accepted: bool, chat_id: int = 0, can_mute: bool = False):
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in member_tools.__init__: %s", tg_id)
        self.tg_id = 0
    else:
        self.tg_id = tg_id
    self.private = private
    self.accepted = accepted
    self.chat_id = chat_id
    self.can_mute = can_mute