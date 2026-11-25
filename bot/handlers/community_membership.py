from aiogram import types
from aiogram.filters import Command

from utils.validation import Validation

router = Router()

@router.message(Command("community"))
async def community_command(message: types.Message):
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in community_command: %s", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    # rest of handler logic