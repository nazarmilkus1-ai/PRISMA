async def _telegram_member(bot: Bot, tg_id: int):
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in _telegram_member: %s", error)
        return None
    try:
        return await bot.get_chat_member(MODERATION_GROUP_ID, tg_id)
    except TelegramBadRequest as exc:
        if _is_missing_member_error(exc):
            return None
        raise
