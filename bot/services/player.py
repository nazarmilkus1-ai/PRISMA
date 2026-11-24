"""Player-facing helpers: profile, link, stats, etc."""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from html import escape

from db.player import get_player_profile, get_player_stats, get_player_top
from db.rpc import bot_get_player_link, bot_link_player, bot_unlink_player
from services.validation import TgIdValidation

log = logging.getLogger(__name__)


def _safe_tg_id(tg_id: int | None, context: str) -> int | None:
    """Вернуть tg_id если валидный, иначе None с логом."""
    try:
        return TgIdValidation.validate(tg_id, context)
    except ValueError:
        return None


async def profile_text(tg_id: int) -> str:
    safe_id = _safe_tg_id(tg_id, "player.profile_text")
    if safe_id is None:
        return "❌ Не удалось загрузить профиль: некорректный идентификатор."
    profile = await get_player_profile(safe_id)
    if not profile:
        return "👤 <b>Профиль</b>\n\nПрофиль не найден. Привяжите аккаунт через /link."
    lines = ["👤 <b>Профиль</b>", ""]
    lines.append(f"<b>Ник:</b> {escape(profile.get('username', '—'))}")
    lines.append(f"<b>UUID:</b> <code>{profile.get('uuid', '—')}</code>")
    lines.append(f"<b>Роль:</b> {escape(profile.get('role', '—'))}")
    linked = profile.get('telegram_id')
    lines.append(f"<b>Telegram:</b> {'привязан' if linked else 'не привязан'}")
    created = profile.get('created_at')
    if created:
        dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
        lines.append(f"<b>Регистрация:</b> {dt.strftime('%d.%m.%Y')}")
    return "\n".join(lines)


async def link_player(tg_id: int, username: str) -> tuple[bool, str]:
    safe_id = _safe_tg_id(tg_id, "player.link_player")
    if safe_id is None:
        return False, "❌ Некорректный идентификатор Telegram."
    result = await bot_link_player(safe_id, username)
    if result.error:
        return False, f"❌ Ошибка привязки: {result.error}"
    data = result.data or {}
    if not data.get('success'):
        return False, f"❌ {data.get('error', 'Неизвестная ошибка')}"
    return True, f"✅ Аккаунт <b>{escape(username)}</b> привязан к вашему Telegram."


async def unlink_player(tg_id: int) -> tuple[bool, str]:
    safe_id = _safe_tg_id(tg_id, "player.unlink_player")
    if safe_id is None:
        return False, "❌ Некорректный идентификатор Telegram."
    result = await bot_unlink_player(safe_id)
    if result.error:
        return False, f"❌ Ошибка отвязки: {result.error}"
    data = result.data or {}
    if not data.get('success'):
        return False, f"❌ {data.get('error', 'Неизвестная ошибка')}"
    return True, "✅ Аккаунт отвязан от Telegram."


async def stats_text(tg_id: int) -> str:
    safe_id = _safe_tg_id(tg_id, "player.stats_text")
    if safe_id is None:
        return "❌ Не удалось загрузить статистику: некорректный идентификатор."
    stats = await get_player_stats(safe_id)
    if not stats:
        return "📊 <b>Статистика</b>\n\nСтатистика не найдена."
    lines = ["📊 <b>Статистика</b>", ""]
    lines.append(f"<b>Блоков установлено:</b> {stats.get('blocks_placed', 0):,}")
    lines.append(f"<b>Блоков сломано:</b> {stats.get('blocks_broken', 0):,}")
    lines.append(f"<b>Время в игре:</b> {stats.get('playtime', 0)} мин")
    lines.append(f"<b>Смертей:</b> {stats.get('deaths', 0)}")
    lines.append(f"<b>Убийств:</b> {stats.get('kills', 0)}")
    return "\n".join(lines)


async def top_text(tg_id: int, category: str = "blocks_placed", limit: int = 10) -> str:
    safe_id = _safe_tg_id(tg_id, "player.top_text")
    if safe_id is None:
        return "❌ Не удалось загрузить топ: некорректный идентификатор."
    top_list = await get_player_top(category, limit)
    if not top_list:
        return f"🏅 <b>Топ по {category}</b>\n\nПока пусто."
    lines = [f"🏅 <b>Топ по {category}</b>", ""]
    for i, row in enumerate(top_list, 1):
        name = escape(row.get('username', '—'))
        value = row.get(category, 0)
        lines.append(f"{i}. {name} — {value:,}")
    return "\n".join(lines)


async def check_link(tg_id: int) -> tuple[bool, str | None]:
    safe_id = _safe_tg_id(tg_id, "player.check_link")
    if safe_id is None:
        return False, None
    result = await bot_get_player_link(safe_id)
    if result.error or not result.data:
        return False, None
    data = result.data
    return data.get('linked', False), data.get('username')
