"""/guide — "what do I do next?" checklist that follows the user's real status."""
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db.rpc import bot_get_profile, bot_get_user_status

router = Router(name="guide")


def build_guide(status: str, profile: dict) -> tuple[str, InlineKeyboardMarkup | None]:
    nick = str(profile.get("minecraft_nickname") or "").strip()
    whitelisted = bool(profile.get("is_whitelisted"))
    accepted = status == "ACCEPTED"
    pending = status == "PENDING"

    app_mark = "✅" if accepted else ("⏳" if pending else "⬜")
    steps = [
        "✅ Открыть бота",
        f"{app_mark} Подать заявку" + (" — на рассмотрении" if pending else ""),
        f"{'✅' if accepted and whitelisted else '⬜'} Получить доступ (whitelist)",
        f"{'✅' if nick else '⬜'} Minecraft-ник" + (f": <code>{escape(nick)}</code>" if nick else ""),
        f"{'⬜' if accepted else '🔒'} Зайти на сервер",
    ]

    rows: list[list[InlineKeyboardButton]] = []
    if status in ("NO_USER", "NO_APPLICATION", "REJECTED", ""):
        hint = "Подайте заявку — это около минуты."
        if status == "REJECTED":
            hint = "Прошлая заявка отклонена. Можно подать новую, когда закончится ожидание."
        rows.append([InlineKeyboardButton(text="📝 Подать заявку", callback_data="apply")])
        rows.append([InlineKeyboardButton(text="📜 Правила", callback_data="rules")])
    elif pending:
        hint = "Заявка у администрации. Решение придёт сюда, в бота — ничего делать не нужно."
    elif accepted and not whitelisted:
        hint = "Заявка одобрена. Доступ на сервер включается автоматически — это занимает пару минут."
    elif accepted and not nick:
        hint = "Укажите Minecraft-ник, чтобы получить доступ на сервер."
        rows.append([InlineKeyboardButton(text="🔗 Указать ник", callback_data="menu:link")])
    elif accepted:
        hint = "Всё готово! Адрес и онлайн сервера — в «Сервер». Приятной игры 🌙"
        rows.append([InlineKeyboardButton(text="🖥 Сервер", callback_data="player:server"),
                     InlineKeyboardButton(text="👤 Профиль", callback_data="profile")])
    else:
        hint = "Откройте /start."

    text = "🧭 <b>Что дальше?</b>\n\n" + "\n".join(steps) + f"\n\n➡️ {hint}"
    return text, InlineKeyboardMarkup(inline_keyboard=rows) if rows else None


async def _guide_for(tg_id: int):
    status = await bot_get_user_status(tg_id)
    profile: dict = {}
    if status == "ACCEPTED":
        result = await bot_get_profile(tg_id)
        if not result.error and isinstance(result.data, dict) and not result.data.get("error"):
            profile = result.data
    return build_guide(str(status or ""), profile)


@router.message(Command("guide", "гайд"), F.chat.type == "private")
async def guide_command(message: types.Message):
    text, markup = await _guide_for(message.from_user.id)
    await message.answer(text, parse_mode="HTML", reply_markup=markup)


@router.callback_query(F.data == "guide")
async def guide_button(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        text, markup = await _guide_for(callback.from_user.id)
        await callback.message.answer(text, parse_mode="HTML", reply_markup=markup)
