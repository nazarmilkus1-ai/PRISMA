"""Quick actions: the sections a member opens most, remembered in RAM (reset on restart)."""
from __future__ import annotations

import logging
from collections import Counter, OrderedDict

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from utils.validation import Validation

logger = logging.getLogger(__name__)

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


def _validate_tg_id(tg_id: int, action: str) -> bool:
    """Проверяет Telegram ID и логирует предупреждение, если невалиден."""
    ok, msg = Validation.validate_telegram_id(tg_id, "Telegram ID")
    if not ok:
        Validation.log_warning("quick", tg_id, action, msg)
    return ok


def record(tg_id: int, callback_data: str | None) -> None:
    """Записывает использование быстрого действия пользователем."""
    if not _validate_tg_id(tg_id, "record"):
        return
    if callback_data not in ACTIONS:
        Validation.log_warning("quick", tg_id, "record", f"Неизвестное действие: {callback_data}")
        return
    try:
        counter = _usage.get(tg_id)
        if counter is None:
            if len(_usage) >= MAX_USERS:
                _usage.popitem(last=False)
            counter = _usage[tg_id] = Counter()
        else:
            _usage.move_to_end(tg_id)
        counter[callback_data] += 1
    except Exception as e:
        Validation.log_error("quick", tg_id, "record", e, {"callback_data": callback_data})


def top(tg_id: int, limit: int = 4) -> list[str]:
    """Возвращает список самых частых действий пользователя."""
    if not _validate_tg_id(tg_id, "top"):
        return []
    try:
        counter = _usage.get(tg_id)
        return [key for key, _ in counter.most_common(limit)] if counter else []
    except Exception as e:
        Validation.log_error("quick", tg_id, "top", e, {"limit": limit})
        return []


def keyboard(tg_id: int) -> InlineKeyboardMarkup:
    """Строит клавиатуру быстрых действий для пользователя."""
    if not _validate_tg_id(tg_id, "keyboard"):
        # Возвращаем минимальную клавиатуру с кнопкой меню
        return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🏠 Меню", callback_data="menu:back")]])
    try:
        frequent = top(tg_id, 4)
        chosen = list(frequent)
        for key in DEFAULTS:
            if len(chosen) >= 6:
                break
            if key not in chosen:
                chosen.append(key)
        # Защита: если ключа нет в ACTIONS (например, при расширении списка), пропускаем
        buttons = [InlineKeyboardButton(text=ACTIONS[key], callback_data=key) for key in chosen if key in ACTIONS]
        rows = [buttons[i:i + 2] for i in range(0, len(buttons), 2)]
        rows.append([InlineKeyboardButton(text="🏠 Меню", callback_data="menu:back")])
        return InlineKeyboardMarkup(inline_keyboard=rows)
    except Exception as e:
        Validation.log_error("quick", tg_id, "keyboard", e)
        # Fallback: минимальная клавиатура
        return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="🏠 Меню", callback_data="menu:back")]])


def text(tg_id: int) -> str:
    """Возвращает текст для блока быстрых действий."""
    if not _validate_tg_id(tg_id, "text"):
        return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап."
    try:
        if top(tg_id, 1):
            return "⚡ <b>Быстрые действия</b>\nСверху — то, чем вы пользуетесь чаще всего."
        return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап. Со временем здесь появятся ваши любимые."
    except Exception as e:
        Validation.log_error("quick", tg_id, "text", e)
        return "⚡ <b>Быстрые действия</b>\nЧасто нужные разделы в один тап."
