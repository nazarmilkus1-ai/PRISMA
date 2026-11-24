"""Quick actions: the sections a member opens most, remembered in RAM (reset on restart)."""
from __future__ import annotations

from collections import Counter, OrderedDict

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from services.validation import TgIdValidation

log = logging.getLogger(__name__)

# callback_data -> button label. Only navigation targets that are safe to open with one tap.
ACTIONS: dict[str, str] = {
    "profile": "👤 Профиль", "player:server": "🖥 Сервер", "player:stats": "📊 Статистика",
    "player:top": "🏅 Топ", "player:events": "🎯 Ивенты", "clans": "⚔️ Кланы",
    "news": "📰 Новости", "polls": "🗳 Голосования", "reports": "📢 Жалоба", "support": "🆘 Поддержка",
    "ask": "🤖 PRISMA_AI", "player:achievements": "🏆 Достижения", "player:notifications": "🔔 Уведомления",
}
DEFAULTS = ("player:server", "player:events", "ask", "profile", "player:stats")
MAX_USERS = 5000

_usage: "OrderedDict[int, Counter]" = OrderedDict()


def _safe_tg_id(tg_id: int | None, context: str) -> int | None:
    """Вернуть tg_id если валидный, иначе None с логом."""
    try:
        return TgIdValidation.validate(tg_id, context)
    except ValueError:
        return None


def record(tg_id: int, callback_data: str | None) -> None:
    safe_id = _safe_tg_id(tg_id, "quick.record")
    if safe_id is None:
        return
    if callback_data not in ACTIONS:
        return
    counter = _usage.get(safe_id)
    if counter is None:
        if len(_usage) >= MAX_USERS:
            _usage.popitem(last=False)
        counter = _usage[safe_id] = Counter()
    else:
        _usage.move_to_end(safe_id)
    counter[callback_data] += 1


def top(tg_id: int, limit: int = 4) -> list[str]:
    safe_id = _safe_tg_id(tg_id, "quick.top")
    if safe_id is None:
        return []
    counter = _usage.get(safe_id)
    return [key for key, _ in counter.most_common(limit)] if counter else []


def keyboard(tg_id: int) -> InlineKeyboardMarkup:
    safe_id = _safe_tg_id(tg_id, "quick.keyboard")
    if safe_id is None:
        # Вернуть клавиатуру с дефолтными кнопками
        chosen = list(DEFAULTS[:6])
        buttons = [InlineKeyboardButton(text=ACTIONS[key], callback_data=key) for key in chosen]
        rows = [buttons[i:i + 2] for i in range(0, len(buttons), 2)]
        rows.append([InlineKeyboardButton(text="🏠 Меню", callback_data="menu:back")])
        return InlineKeyboardMarkup(inline_keyboard=rows)
    frequent = top(safe_id, 4)
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
    safe_id = _safe_tg_id(tg_id, "quick.text")
    if safe_id is None:
        return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап. Со временем здесь появятся ваши любимые."
    if top(safe_id, 1):
        return "⚡ <b>Быстрые действия</b>\nСверху — то, чем вы пользуетесь чаще всего."
    return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап. Со временем здесь появятся ваши любимые.
