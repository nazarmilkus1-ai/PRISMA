"""Reminders: time parsing and thin wrappers around the reminder RPCs.

A reminder is delivered by the notification worker at its time, so nothing is scheduled in RAM
and reminders survive restarts. Times are interpreted in Europe/Kyiv.
"""
from __future__ import annotations

import os
import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from db.rpc import bot_cancel_reminder, bot_create_reminder, bot_list_reminders

TZ = ZoneInfo(os.getenv("REMINDER_TZ", "Europe/Kyiv"))

_UNIT = {"м": 1, "мин": 1, "минут": 1, "минуты": 1, "минуту": 1, "m": 1, "min": 1,
         "ч": 60, "час": 60, "часа": 60, "часов": 60, "h": 60,
         "д": 1440, "дн": 1440, "день": 1440, "дня": 1440, "дней": 1440, "d": 1440}
_REL = re.compile(r"^(?:через\s+|in\s+)?(\d{1,4})\s*([a-zа-я]+)\s+(.+)$", re.I | re.S)
_CLOCK = re.compile(r"^(?:(сегодня|завтра|послезавтра)\s+)?(?:в\s+|at\s+)?(\d{1,2})[:.](\d{2})\s+(.+)$", re.I | re.S)
_FULL = re.compile(r"^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2})[:.](\d{2})\s+(.+)$", re.S)


def now_local() -> datetime:
    return datetime.now(TZ)


def parse(text: str, now: datetime | None = None) -> tuple[datetime, str] | None:
    """`30м текст`, `через 2 часа текст`, `14:30 текст`, `завтра 09:00 текст`, `2026-12-01 18:00 текст`."""
    text = (text or "").strip()
    now = now or now_local()
    match = _FULL.match(text)
    if match:
        y, mo, d, h, mi, rest = match.groups()
        try:
            return datetime(int(y), int(mo), int(d), int(h), int(mi), tzinfo=TZ), rest.strip()
        except ValueError:
            return None
    match = _REL.match(text)
    if match and match.group(2).lower() in _UNIT:
        minutes = int(match.group(1)) * _UNIT[match.group(2).lower()]
        return now + timedelta(minutes=minutes), match.group(3).strip()
    match = _CLOCK.match(text)
    if match:
        day_word, h, mi, rest = match.groups()
        try:
            target = now.replace(hour=int(h), minute=int(mi), second=0, microsecond=0)
        except ValueError:
            return None
        shift = {"завтра": 1, "послезавтра": 2}.get((day_word or "").lower(), 0)
        target += timedelta(days=shift)
        if target <= now + timedelta(seconds=30) and not day_word:
            target += timedelta(days=1)  # "14:30" already passed today → tomorrow
        return target, rest.strip()
    return None


ERRORS = {
    "REMINDER_TIME_PAST": "Это время уже прошло или слишком близко.",
    "REMINDER_TIME_TOO_FAR": "Напоминания можно ставить не дальше чем на год вперёд.",
    "REMINDER_LIMIT": "Уже стоит 20 напоминаний — отмените лишние: /reminders",
    "REMINDER_TEXT_INVALID": "Текст напоминания: от 1 до 300 символов.",
}


def friendly_error(raw: object) -> str:
    text = str(raw)
    for code, message in ERRORS.items():
        if code in text:
            return message
    return "Не получилось поставить напоминание. Попробуйте ещё раз."


def fmt(when: datetime | str) -> str:
    if isinstance(when, str):
        when = datetime.fromisoformat(when.replace("Z", "+00:00"))
    return when.astimezone(TZ).strftime("%d.%m %H:%M")


async def create(tg_id: int, text: str, when: datetime) -> tuple[bool, str]:
    """(ok, message). The message is ready to show to the user."""
    result = await bot_create_reminder(tg_id, text, when.isoformat())
    if result.error:
        return False, friendly_error(result.error)
    return True, f"⏰ Напомню {fmt(when)} (Киев): {text}"


async def listing(tg_id: int) -> list[dict]:
    result = await bot_list_reminders(tg_id)
    return result.data if not result.error and isinstance(result.data, list) else []


async def cancel(tg_id: int, reminder_id: str) -> bool:
    result = await bot_cancel_reminder(tg_id, reminder_id)
    return bool(result.data) and not result.error
