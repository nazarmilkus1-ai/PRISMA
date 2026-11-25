from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup

from utils.validation import Validation

router = Router(name="chat_commands")


async def some_chat_command(message: types.Message):
    tg_id = message.from_user.id
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in chat command: %s", tg_id)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    # rest of command logic