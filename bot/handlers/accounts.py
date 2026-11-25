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