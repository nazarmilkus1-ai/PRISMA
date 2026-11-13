"""/accounts, /addaccount, /removeaccount — a second Minecraft account (other platform);
/addtg, /linktg, /removetg — a second Telegram account for the same profile."""
from __future__ import annotations

from html import escape

from aiogram import BaseMiddleware, Router, types
from aiogram.filters import Command, CommandObject

from db.rpc import (
    bot_add_minecraft_account,
    bot_list_minecraft_accounts,
    bot_remove_minecraft_account,
    bot_telegram_alias_create,
    bot_telegram_alias_remove,
)
from services import accounts
from utils.permissions import DENIED_MESSAGE, is_approved

router = Router(name="accounts")

_PLATFORMS = {"java": "JAVA", "джава": "JAVA", "bedrock": "BEDROCK", "бедрок": "BEDROCK", "бэдрок": "BEDROCK"}


class TelegramAliasMiddleware(BaseMiddleware):
    """In the private chat a linked second Telegram account acts as its primary profile.

    Replies still go to the chat the message came from; only the identity handlers see is the profile's.
    """

    async def __call__(self, handler, event, data):
        try:
            user = getattr(event, "from_user", None)
            chat = event.chat if isinstance(event, types.Message) else getattr(getattr(event, "message", None), "chat", None)
            if user and not user.is_bot and chat is not None and chat.type == "private":
                primary = await accounts.primary_for(user.id)
                if primary and primary != user.id:
                    mapped = user.model_copy(update={"id": primary, "username": None})
                    event = event.model_copy(update={"from_user": mapped})
                    data["event_from_user"] = mapped
        except Exception:  # identity mapping must never take the bot down
            pass
        return await handler(event, data)


def _line(row: dict) -> str:
    platform = str(row.get("platform") or "").upper()
    icon = "☕" if platform == "JAVA" else "📱"
    shown = row.get("gamertag") or row.get("nickname") or "—"
    server = row.get("nickname")
    suffix = f" → на сервере <code>{escape(str(server))}</code>" if row.get("gamertag") and server else ""
    return f"{icon} {escape(platform.title())}: <b>{escape(str(shown))}</b>{suffix}"


@router.message(Command("accounts"))
async def cmd_accounts(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    result = await bot_list_minecraft_accounts(message.from_user.id)
    if result.error or not isinstance(result.data, dict) or result.data.get("error"):
        await message.answer("❌ Не удалось получить аккаунты.")
        return
    primary = result.data.get("primary") or {}
    extra = result.data.get("extra") or []
    lines = ["🎮 <b>Ваши Minecraft-аккаунты</b>", _line(primary)] + [_line(r) for r in extra]
    if not extra:
        lines.append("\nВторой аккаунт (другая платформа): <code>/addaccount bedrock D1lan ok</code>")
    lines.append("Играть двумя аккаунтами одновременно нельзя: статистика, клан и наказания у них общие.")
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("addaccount"))
async def cmd_add_account(message: types.Message, command: CommandObject):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    parts = (command.args or "").split(maxsplit=1)
    platform = _PLATFORMS.get(parts[0].lower()) if parts else None
    if not platform or len(parts) < 2:
        await message.answer("Формат: <code>/addaccount java Steve_01</code> или <code>/addaccount bedrock D1lan ok</code>.\n"
                             "Платформа должна отличаться от основной.", parse_mode="HTML")
        return
    result = await bot_add_minecraft_account(message.from_user.id, platform, parts[1])
    error = result.error or (result.data.get("error") if isinstance(result.data, dict) else None)
    if error:
        await message.answer("❌ " + escape(accounts.MINECRAFT_ERRORS.get(str(error), "Не удалось добавить аккаунт.")))
        return
    data = result.data if isinstance(result.data, dict) else {}
    server = data.get("nickname")
    note = f"\nНа сервере вы будете как <code>{escape(str(server))}</code>." if data.get("gamertag") and server else ""
    await message.answer("✅ Второй аккаунт добавлен. Он сможет зайти на сервер при следующем входе." + note, parse_mode="HTML")


@router.message(Command("removeaccount"))
async def cmd_remove_account(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    result = await bot_remove_minecraft_account(message.from_user.id)
    if result.error or (isinstance(result.data, dict) and result.data.get("error")):
        await message.answer("❌ Не удалось убрать аккаунт.")
        return
    removed = int((result.data or {}).get("removed") or 0) if isinstance(result.data, dict) else 0
    await message.answer("✅ Второй аккаунт убран." if removed else "Второго аккаунта нет.")


@router.message(Command("addtg"))
async def cmd_add_tg(message: types.Message):
    if message.chat.type != "private":
        await message.answer("Эта команда работает только в личке с ботом.")
        return
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    code = accounts.new_code(message.from_user.id)
    await message.answer(
        "🔗 Откройте бота со <b>второго</b> Telegram-аккаунта и отправьте:\n"
        f"<code>/linktg {code}</code>\n\nКод одноразовый и действует 10 минут. Никому его не показывайте.",
        parse_mode="HTML",
    )


@router.message(Command("linktg"))
async def cmd_link_tg(message: types.Message, command: CommandObject):
    if message.chat.type != "private":
        await message.answer("Эта команда работает только в личке с ботом.")
        return
    primary = accounts.take_code(command.args or "")
    if primary is None:
        await message.answer("❌ Код неверный или устарел. Получите новый на основном аккаунте: /addtg")
        return
    result = await bot_telegram_alias_create(primary, message.from_user.id)
    error = result.error or (result.data.get("error") if isinstance(result.data, dict) else None)
    if error:
        await message.answer("❌ " + escape(accounts.TELEGRAM_ERRORS.get(str(error), "Не удалось привязать аккаунт.")))
        return
    accounts.forget(message.from_user.id)
    await message.answer("✅ Готово: этот аккаунт теперь работает как ваш профиль PRISMA в личке с ботом.")
    try:
        await message.bot.send_message(primary, "✅ Второй Telegram-аккаунт привязан. Отвязать: /removetg")
    except Exception:
        pass


@router.message(Command("removetg"))
async def cmd_remove_tg(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    result = await bot_telegram_alias_remove(message.from_user.id)
    if result.error:
        await message.answer("❌ Не удалось отвязать аккаунт.")
        return
    accounts.forget()
    await message.answer("✅ Второй Telegram-аккаунт отвязан.")
