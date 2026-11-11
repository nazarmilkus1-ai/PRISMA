"""Quick actions: the sections a member opens most, remembered in RAM (reset on restart)."""
from __future__ import annotations

from collections import Counter, OrderedDict

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

# callback_data -> button label. Only navigation targets that are safe to open with one tap.
ACTIONS: dict[str, str] = {
    "profile": "👤 Профиль", "player:server": "🖥 Сервер", "player:stats": "📊 Статистика",
    "player:top": "🏅 Топ", "player:events": "🎯 Ивенты", "clans": "⚔️ Кланы", "market": "🛒 Рынок",
    "news": "📰 Новости", "polls": "🗳 Голосования", "reports": "📢 Жалоба", "support": "🆘 Поддержка",
    "ask": "🤖 PRISMA_AI", "player:achievements": "🏆 Достижения", "player:notifications": "🔔 Уведомления",
}
DEFAULTS = ("player:server", "player:events", "ask", "profile", "market", "player:stats")
MAX_USERS = 5000

_usage: "OrderedDict[int, Counter]" = OrderedDict()


def record(tg_id: int, callback_data: str | None) -> None:
    if callback_data not in ACTIONS:
        return
    counter = _usage.get(tg_id)
    if counter is None:
        if len(_usage) >= MAX_USERS:
            _usage.popitem(last=False)
        counter = _usage[tg_id] = Counter()
    else:
        _usage.move_to_end(tg_id)
    counter[callback_data] += 1


def top(tg_id: int, limit: int = 4) -> list[str]:
    counter = _usage.get(tg_id)
    return [key for key, _ in counter.most_common(limit)] if counter else []


def keyboard(tg_id: int) -> InlineKeyboardMarkup:
    frequent = top(tg_id, 4)
    chosen = list(frequent)
    for key in DEFAULTS:
        if len(chosen) >= 6:
            break
        if key not in chosen:
            chosen.append(key)
    buttons = [InlineKeyboardButton(text=ACTIONS[key], callback_data=key) for key in chosen]
    rows = [buttons[i:i + 2] for i in range(0, len(buttons), 2)]
    rows.append([InlineKeyboardButton(text="🏠 Меню", callback_data="menu:back")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def text(tg_id: int) -> str:
    if top(tg_id, 1):
        return "⚡ <b>Быстрые действия</b>\nСверху — то, чем вы пользуетесь чаще всего."
    return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап. Со временем здесь появятся ваши любимые."
