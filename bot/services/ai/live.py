"""Live, code-first answers for members: the asker's own data and public server state.

Only the asker's own rows are read (every RPC is keyed by their Telegram ID) or public state
(server, events). No model is involved, so nothing here can be steered by prompt text.
"""
from __future__ import annotations

import re
from html import escape

from db.player import get_online_players, get_own_punishments, get_server_metrics, get_stats, list_events, _user
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db.rpc import bot_get_clan_info, bot_get_server_status

_INTENTS: tuple[tuple[str, re.Pattern, bool], ...] = (
    ("online", re.compile(r"кто (сейчас )?(онлайн|играет|на сервере)|сколько (человек|игроков|людей).*(онлайн|сервер)|онлайн (сейчас|на сервере)|сервер (работает|жив|лежит)", re.I), False),
    ("stats", re.compile(r"(моя|мою|мои)\s+(статистик|активност)|сколько я (играл|наиграл)|мой (уровень|рейтинг|xp|опыт|k/?d)", re.I), True),
    ("clan", re.compile(r"(мой|моего|мои)\s+клан|в каком я клане|состою ли я в клан", re.I), True),
    ("punish", re.compile(r"(мои|мое|моё)\s+(наказани|бан|мут|варн)|меня (забанили|замутили|наказали)|почему я (в бане|забанен|замучен)|есть ли у меня (бан|мут|варн|наказани)", re.I), True),
    ("events", re.compile(r"(какие|ближайш|предстоящ|есть ли|когда).{0,20}(ивент|турнир|мероприят)", re.I), False),
)


def live_intent(question: str) -> tuple[str, bool] | None:
    for kind, pattern, personal in _INTENTS:
        if pattern.search(question or ""):
            return kind, personal
    return None


async def _online() -> str:
    metrics, _ = await get_server_metrics()
    players, players_err = await get_online_players()
    status = await bot_get_server_status()
    state = status.data.get("status") if not status.error and isinstance(status.data, dict) else None
    names = [str(r.get("minecraft_nickname") or "").strip() for r in players or [] if isinstance(r, dict)]
    names = [n for n in names if n][:30]
    if players_err and not metrics and not state:
        return "❌ Статус сервера сейчас недоступен."
    count = len(names) if not players_err else int((metrics or {}).get("online_players") or 0)
    lines = [f"🖥 <b>Сервер</b>: {escape(str(state or 'unknown').upper())} · онлайн <b>{count}/{(metrics or {}).get('max_players', '—')}</b>"]
    if names:
        lines.append("Сейчас играют: " + ", ".join(f"<code>{escape(n)}</code>" for n in names))
    return "\n".join(lines)


async def _stats(tg_id: int) -> str:
    user, _ = await _user(tg_id)
    stats, err = await get_stats(tg_id)
    if not user or err:
        return "❌ Не удалось загрузить вашу статистику."
    minutes = int(stats.get("playtime_minutes", 0))
    return (
        "📊 <b>Ваша статистика</b>\n"
        f"Уровень / XP: <b>{user.get('level', 1)} / {user.get('xp', 0)}</b> · рейтинг <b>{user.get('rating', 0)}</b>\n"
        f"Игровое время: <b>{minutes // 60} ч. {minutes % 60} мин.</b>\n"
        f"Убийства / смерти: <b>{stats.get('kills', 0)} / {stats.get('deaths', 0)}</b>\n"
        f"Сообщения: <b>{stats.get('chat', 0)}</b> · входов: <b>{stats.get('joins', 0)}</b>"
    )


async def _clan(tg_id: int) -> str:
    result = await bot_get_clan_info(tg_id)
    if result.error or not isinstance(result.data, dict):
        return "❌ Не удалось получить данные клана."
    data = result.data
    if data.get("error") == "NO_CLAN":
        return "⚔️ Вы не состоите в клане. Создать: /clan create, посмотреть список: /clan list."
    return (f"⚔️ <b>[{escape(str(data.get('tag') or '—'))}] {escape(str(data.get('name') or 'Клан'))}</b>\n"
            f"Уровень <b>{data.get('level', 1)}</b> · рейтинг <b>{data.get('rating', 0)}</b> · участников <b>{len(data.get('members') or [])}</b>")


async def _punish(tg_id: int) -> str:
    user, _ = await _user(tg_id)
    rows, err = await get_own_punishments(user["id"]) if user else ([], "no user")
    if err:
        return "❌ Не удалось загрузить наказания."
    active = [r for r in rows if str(r.get("status") or "").upper() == "ACTIVE"]
    if not active:
        return "✅ Активных наказаний у вас нет."
    lines = ["⚖️ <b>Активные наказания</b>"]
    for row in active[:5]:
        lines.append(f"• {escape(str(row.get('type') or '—'))}: {escape(str(row.get('reason') or '—'))[:120]}")
    lines.append("Не согласны? Апелляция: /appeal")
    return "\n".join(lines)


async def _events_card(tg_id: int) -> tuple[str, InlineKeyboardMarkup | None]:
    rows, err = await list_events(tg_id)
    if err:
        return "❌ Не удалось загрузить ивенты.", None
    if not rows:
        return "🎯 Сейчас активных ивентов нет.", links_markup("events")
    lines = ["🎯 <b>Ивенты</b>"]
    buttons: list[list[InlineKeyboardButton]] = []
    for event in rows[:5]:
        lines.append(f"• <b>{escape(str(event.get('title') or event.get('slug') or 'Ивент'))}</b> — {escape(str(event.get('starts_at') or 'время уточняется'))}"
                     + (" ✅" if event.get("registered") else ""))
        if event.get("id") and not event.get("registered") and len(buttons) < 3:
            buttons.append([InlineKeyboardButton(text=f"🎯 Записаться: {str(event.get('title') or 'ивент')[:28]}",
                                                 callback_data=f"cd:evr:{event['id']}")])
    markup = links_markup("events")
    return "\n".join(lines), InlineKeyboardMarkup(inline_keyboard=buttons + list(markup.inline_keyboard))


async def _events(tg_id: int) -> str:
    return (await _events_card(tg_id))[0]


_LINKS = {
    "online": [("🖥 Сервер на сайте", "/server"), ("📈 Состояние", "/status")],
    "stats": [("🏆 Рейтинги", "/rankings"), ("📜 Достижения: /guide", "/guide")],
    "clan": [("⚔️ Все кланы", "/clans")],
    "punish": [("📜 Правила", "/rules")],
    "events": [("🌐 Все ивенты", "/events")],
}


def links_markup(kind: str) -> InlineKeyboardMarkup | None:
    """Site shortcuts under a live answer: members tap instead of typing the next question."""
    links = _LINKS.get(kind)
    if not links:
        return None
    from services.cards import site
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=t, url=site(path)) for t, path in links]])


async def live_card(question: str, tg_id: int, accepted: bool, private: bool) -> tuple[str, InlineKeyboardMarkup | None] | None:
    """Same answers as live_answer, plus buttons (event registration, site pages)."""
    found = live_intent(question)
    if not found:
        return None
    kind, personal = found
    if kind == "events" and accepted and (private or not personal):
        return await _events_card(tg_id)
    text = await live_answer(question, tg_id, accepted, private)
    if text is None:
        return None
    return text, (None if text.startswith(("🔒", "❌")) else links_markup(kind))


async def live_answer(question: str, tg_id: int, accepted: bool, private: bool) -> str | None:
    """HTML answer, or None when the question is not a live-data intent (or must not be answered here)."""
    found = live_intent(question)
    if not found:
        return None
    kind, personal = found
    if personal and not private:
        return "🔒 Личные данные показываю только в личных сообщениях с ботом."
    if kind != "online" and not accepted:
        return "🔒 Это открывается после одобрения заявки: /guide"
    if kind == "online":
        return await _online()
    if kind == "stats":
        return await _stats(tg_id)
    if kind == "clan":
        return await _clan(tg_id)
    if kind == "punish":
        return await _punish(tg_id)
    return await _events(tg_id)
