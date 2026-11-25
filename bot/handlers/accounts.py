from __future__ import annotations

from html import escape

from aiogram import BaseMiddleware, Router, types
from aiogram.filters import Command, CommandObject

from utils.validation import Validation

from db.rpc import (
    bot_add_minecraft_account,
    bot_list_minecraft_accounts,
    bot_remove_minecraft_account,
    bot_telegram_alias_create,
    bot_telegram_alias_remove,
)


@router.message(Command("addtg"))
async def cmd_add_tg(message: types.Message):
    tg_id = message.from_user.id
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in cmd_add_tg: %s", tg_id)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    if message.chat.type != "private":
        await message.answer("Эта команда работает только в личке с ботом.")
        return
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return


@router.message(Command("linktg"))
async def cmd_link_tg(message: types.Message, command: CommandObject):
    if message.chat.type != "private":
        await message.answer("Эта команда работает только в личке с ботом.")
        return
    tg_id = message.from_user.id
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in cmd_link_tg: %s", tg_id)
        await message.answer("❌ Неверный идентификатор пользователя.")
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
    tg_id = message.from_user.id
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in cmd_remove_tg: %s", tg_id)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    result = await bot_telegram_alias_remove(message.from_user.id)
    if result.error:
        await message.answer("❌ Не удалось отвязать аккаунт.")
        return
    accounts.forget()
    await message.answer("✅ Второй Telegram-аккаунт отвязан.")