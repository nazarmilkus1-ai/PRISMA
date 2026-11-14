"""One card format for the whole bot: title, key facts, and action buttons.

Cards are what people tap instead of typing: an event
with «Записаться», the server status with «Открыть сайт». Every callback is `cd:<action>:<arg>`
(≤ 64 bytes) and is handled in handlers/cards.py, which re-checks the member before doing anything.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from html import escape

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

import config

Button = tuple[str, str]  # (text, callback_data | https url)


@dataclass
class Card:
    title: str
    facts: list[tuple[str, str]] = field(default_factory=list)
    note: str = ""
    rows: list[list[Button]] = field(default_factory=list)


def _button(text: str, target: str) -> InlineKeyboardButton:
    if target.startswith(("http://", "https://")):
        return InlineKeyboardButton(text=text, url=target)
    return InlineKeyboardButton(text=text, callback_data=target[:64])


def render(card: Card) -> tuple[str, InlineKeyboardMarkup | None]:
    lines = [f"<b>{escape(card.title)}</b>"]
    lines += [f"{escape(label)}: {escape(value)}" for label, value in card.facts if value not in ("", None)]
    if card.note:
        lines.append(f"<i>{escape(card.note)}</i>")
    markup = InlineKeyboardMarkup(inline_keyboard=[[_button(t, d) for t, d in row] for row in card.rows]) if card.rows else None
    return "\n".join(lines), markup


def site(path: str) -> str:
    return f"{config.SITE_URL.rstrip('/')}{path}"


def _when(value) -> str:
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).strftime("%d.%m %H:%M")
    except ValueError:
        return ""


def event(row: dict) -> Card:
    rows: list[list[Button]] = []
    if row.get("id") and not row.get("registered"):
        rows.append([("🎯 Записаться", f"cd:evr:{row['id']}")])
    rows.append([("🌐 События на сайте", site("/events"))])
    return Card(title=f"🎯 {row.get('title') or 'Ивент'}",
                facts=[("Начало", _when(row.get("starts_at"))), ("Вы", "записаны ✅" if row.get("registered") else "")], rows=rows)


def server_status(online: bool, players: int | None = None, max_players: int | None = None) -> Card:
    facts = [("Состояние", "онлайн ✅" if online else "не на связи ❌")]
    if online and players is not None:
        facts.append(("Игроков", f"{players}" + (f" / {max_players}" if max_players else "")))
    return Card(title="🖥 Сервер PRISMA", facts=facts,
                rows=[[("🌐 Состояние на сайте", site("/status"))]])
