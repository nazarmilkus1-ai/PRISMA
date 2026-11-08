"""Daily staff briefing: counts of what is waiting. Code only, no model needed."""
import asyncio
import logging
import os
from datetime import datetime
from zoneinfo import ZoneInfo

from aiogram import Bot

from config import ADMIN_GROUP_ID, OWNER_TG_ID
from db.admin import open_appeals, open_reports
from db.rpc import bot_get_pending_count, bot_list_inactive_members

logger = logging.getLogger(__name__)

TZ = ZoneInfo(os.getenv("BRIEFING_TZ", "Europe/Kyiv"))
HOUR = int(os.getenv("BRIEFING_HOUR", "10"))


async def build_briefing() -> str | None:
    """Return the briefing text, or None when there is nothing to report."""
    applications = await bot_get_pending_count()
    reports = appeals = None
    if OWNER_TG_ID:
        rows, err = await open_reports(OWNER_TG_ID, 50)
        reports = None if err else len(rows)
        rows, err = await open_appeals(OWNER_TG_ID, 50)
        appeals = None if err else len(rows)
    inactive = await bot_list_inactive_members(7, 100)
    inactive_count = len(inactive.data) if not inactive.error and isinstance(inactive.data, list) else None

    lines = ["☀️ <b>Утренний брифинг PRISMA</b>", ""]
    waiting = 0
    if isinstance(applications, int):
        waiting += applications
        lines.append(f"📋 Заявок ждут решения: <b>{applications}</b>")
    if reports is not None:
        waiting += reports
        lines.append(f"📢 Открытых репортов: <b>{reports}</b>")
    if appeals is not None:
        waiting += appeals
        lines.append(f"⚖️ Открытых апелляций: <b>{appeals}</b>")
    if inactive_count is not None:
        lines.append(f"✖️ Неактивны больше недели: <b>{inactive_count}</b> (/неактив)")
    if not waiting:
        return None  # nothing needs a decision: stay quiet
    lines += ["", "Откройте бота → /admin, чтобы разобрать очередь."]
    return "\n".join(lines)


async def run_briefing_worker(bot: Bot, stop_event: asyncio.Event):
    if not ADMIN_GROUP_ID:
        logger.info("Briefing disabled: ADMIN_GROUP_ID is not configured")
        return
    last_sent_on = None
    while not stop_event.is_set():
        now = datetime.now(TZ)
        if now.hour >= HOUR and last_sent_on != now.date():
            try:
                text = await build_briefing()
                if text:
                    await bot.send_message(ADMIN_GROUP_ID, text, parse_mode="HTML", disable_notification=True)
                last_sent_on = now.date()
            except Exception:
                logger.exception("Briefing failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=600)
        except asyncio.TimeoutError:
            pass
