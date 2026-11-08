from aiogram import F, Router, types
from aiogram.filters import Command

from utils.rules import rules_text

router = Router(name="rules")


@router.message(Command("rules", "правила"))
async def rules_command(message: types.Message):
    await message.answer(rules_text(), parse_mode="HTML")


@router.callback_query(F.data == "rules")
async def rules_button(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await callback.message.answer(rules_text(), parse_mode="HTML")
