from aiogram import types
from db.rpc import bot_find_user, bot_touch_user
from utils.validation import Validation


async def _resolve_target(message: types.Message, args: list[str]):
    reply = message.reply_to_message
    if reply and reply.from_user and not reply.from_user.is_bot:
        u = reply.from_user
        # Валидация Telegram ID из reply
        valid, error = Validation.validate_telegram_id(u.id)
        if not valid:
            Validation.log_warning("Resolve target", u.id, "reply", error)
            return None, args
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
        Validation.log_warning("Resolve target", 0, "bot_find_user", result.error or "неизвестная ошибка")
        return None, args

    target = dict(result.data)
    # Валидация Telegram ID из результата поиска
    tg_id = target.get("tg_id")
    if tg_id is not None:
        valid, error = Validation.validate_telegram_id(tg_id)
        if not valid:
            Validation.log_warning("Resolve target", tg_id, "bot_find_user", error)
            return None, args

    if "username" not in target and "telegram_username" in target:
        target["username"] = target.get("telegram_username")
    if "minecraft_nick" not in target and "minecraft_nickname" in target:
        target["minecraft_nick"] = target.get("minecraft_nickname")
    return target, args[1:]
