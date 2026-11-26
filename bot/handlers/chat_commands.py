async def _resolve_target(message: types.Message, args: list[str]):
    valid, error = Validation.validate_telegram_id(message.from_user.id, "Telegram ID целей")
    if not valid:
        logger.warning("_resolve_target: invalid tg_id %s", message.from_user.id)
        await message.answer("❌ Неверный Telegram ID.")
        return None, args
    reply = message.reply_to_message
    if reply and reply.from_user and not reply.from_user.is_bot:
        u = reply.from_user
        await bot_touch_user(
            u.id,
            u.username or "",
            u.first_name or "",
            u.last_name or "",
            u.full_name,
            "GROUP",
        )
        return {
            "tg_id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "minecraft_nick": None,
        }, args

    if not args:
        return None, args

    target = args[0]
    result = await bot_find_user(target)
    if result.error or not isinstance(result.data, dict) or result.data.get("error"):
        return None, args

    target = dict(result.data)
    if "username" not in target and "telegram_username" in target:
        target["username"] = target.get("telegram_username")
    if "minecraft_nick" not in target and "minecraft_nickname" in target:
        target["minecraft_nick"] = target.get("minecraft_nickname")
    return target, args[1:]