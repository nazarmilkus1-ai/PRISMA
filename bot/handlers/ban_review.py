from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup

from utils.validation import Validation

router = Router(name="ban_review")


async def some_handler(tg_id: int) -> None:
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in ban_review: %s", error)
        return
    # rest of handler logic