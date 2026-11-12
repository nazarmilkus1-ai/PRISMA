from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from services import reminders

router = Router(name="reminders")

HELP = (
    "⏰ <b>Напоминания</b>\n"
    "<code>/remind 30м позвонить</code>\n"
    "<code>/remind через 2 часа проверить заявки</code>\n"
    "<code>/remind 18:30 ивент</code> · <code>/remind завтра 09:00 рынок</code>\n"
    "<code>/remind 2026-12-01 18:00 сезон</code>\n"
    "Список и отмена: /reminders. Можно и просто попросить PRISMA_AI: «напомни через час…»."
)


@router.message(Command("remind", "напомни", "напомнить"), F.chat.type == "private")
async def remind(message: types.Message, command: CommandObject):
    parsed = reminders.parse(command.args or "")
    if not parsed or not parsed[1]:
        await message.answer(HELP, parse_mode="HTML")
        return
    when, text = parsed
    _, reply = await reminders.create(message.from_user.id, text[:300], when)
    await message.answer(escape(reply), parse_mode="HTML")


async def _render(tg_id: int):
    rows = await reminders.listing(tg_id)
    if not rows:
        return "⏰ Напоминаний нет. Поставить: /remind 30м текст", None
    lines = ["⏰ <b>Ваши напоминания</b>"] + [f"• {reminders.fmt(r['at'])} — {escape(str(r['text']))}" for r in rows]
    buttons = [[InlineKeyboardButton(text=f"✖ {reminders.fmt(r['at'])} {str(r['text'])[:18]}", callback_data=f"rm:x:{r['id']}")] for r in rows]
    return "\n".join(lines), InlineKeyboardMarkup(inline_keyboard=buttons)


@router.message(Command("reminders", "напоминания"), F.chat.type == "private")
async def reminders_list(message: types.Message):
    text, markup = await _render(message.from_user.id)
    await message.answer(text, parse_mode="HTML", reply_markup=markup)


@router.callback_query(F.data.startswith("rm:x:"))
async def reminder_cancel(callback: types.CallbackQuery):
    reminder_id = (callback.data or "").split(":", 2)[2]
    ok = await reminders.cancel(callback.from_user.id, reminder_id)
    await callback.answer("Напоминание отменено." if ok else "Уже сработало или отменено.")
    if callback.message:
        text, markup = await _render(callback.from_user.id)
        try:
            await callback.message.edit_text(text, parse_mode="HTML", reply_markup=markup)
        except Exception:
            pass
