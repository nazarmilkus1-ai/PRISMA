"""Moderation action confirmed from a PRISMA_AI card.

Same rules as the /mute command: a live staff identity in admin mode with the `punishment.mute`
permission, the punishment is stored through the same RPC (so history, auto-ban counters and
expiry stay correct), and only then Telegram is asked to restrict the member in the community group.
Nothing here runs without the confirm tap of the staff member who asked.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import config
from db.rpc import bot_check_admin_permission, bot_create_punishment
from utils.chat_permissions import muted_chat_permissions
from utils.permissions import is_admin_mode

logger = logging.getLogger(__name__)

MIN_MINUTES = 1
MAX_MINUTES = 7 * 24 * 60
DEFAULT_MINUTES = 60


async def can_mute(admin_id: int) -> bool:
    if not await is_admin_mode(admin_id):
        return False
    result = await bot_check_admin_permission(admin_id, "punishment.mute")
    return not result.error and bool(result.data)


def clamp_minutes(value) -> int:
    try:
        minutes = int(value)
    except (TypeError, ValueError):
        return DEFAULT_MINUTES
    return max(MIN_MINUTES, min(MAX_MINUTES, minutes))


async def apply_mute(bot, admin_id: int, payload: dict) -> tuple[bool, str]:
    """Returns (ok, text for the card)."""
    if not await can_mute(admin_id):
        return False, "❌ Недостаточно прав: нужен режим админа и право на муты."
    target = int(payload["tg_id"])
    if target == admin_id:
        return False, "❌ Себя замутить нельзя."
    minutes = clamp_minutes(payload.get("minutes"))
    reason = str(payload.get("reason") or "по просьбе администратора в чате")[:200]
    result = await bot_create_punishment(target, "mute", reason, admin_id, minutes, "manual", None)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        return False, "❌ Не удалось выдать мут (проверьте, что игрок зарегистрирован в PRISMA и не из персонала)."
    group = config.MODERATION_GROUP_ID
    name = payload.get("name") or target
    if group:
        try:
            await bot.restrict_chat_member(
                group, target, permissions=muted_chat_permissions(),
                until_date=datetime.now(timezone.utc) + timedelta(minutes=minutes),
                use_independent_chat_permissions=True)
        except Exception as exc:
            logger.warning("telegram mute failed: %s", exc)
            return True, f"⚠️ Мут для {name} сохранён в PRISMA, но Telegram-группа не приняла ограничение."
    return True, f"🔇 {name} в муте на {minutes} мин."
