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


def _is_active_member(member) -> bool:
    if member is None:
        return False
    return member.status in (ChatMemberStatus.OWNER, ChatMemberStatus.ADMINISTRATOR, ChatMemberStatus.MEMBER)


def _is_admin(member) -> bool:
    if member is None:
        return False
    return member.status in (ChatMemberStatus.OWNER, ChatMemberStatus.ADMINISTRATOR)


def _is_missing_member_error(exc: Exception) -> bool:
    return "member is not a member of the chat" in str(exc)


def _text_only_permissions() -> types.ChatPermissions:
    return types.ChatPermissions(can_send_messages=True, can_send_media_messages=True, can_send_polls=True, can_change_info=True, can_pin_messages=True, can_delete_messages=True)
