"""Evening digest of the community chat.

Facts come from the database and the server (online now, who talked most today, how many messages,
upcoming events); the model only turns them into a lively text and may not add anything. If the model is
unavailable a plain template is posted, so the digest never depends on AI. Posted once a day at DIGEST_HOUR
(Kyiv) to the community chat, and on demand with /digest.
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from datetime import datetime
from html import escape
from zoneinfo import ZoneInfo

from aiogram import Bot

import config
from db.rpc import bot_chat_top, bot_chat_top_total, bot_get_community_chat_id, bot_list_events
from services.ai import ambient, live, sanitize
from services.ai.client import AIError, chat_with_fallback, is_configured
from utils.mdhtml import strip_markdown

logger = logging.getLogger(__name__)

TZ = ZoneInfo(os.getenv("DIGEST_TZ", "Europe/Kyiv"))
HOUR = int(os.getenv("DIGEST_HOUR", "20"))
COOLDOWN = 900.0
_TAG = re.compile(r"<[^>]+>")

_enabled: dict[int, bool] = {}
_last_manual: dict[int, float] = {}


def globally_enabled() -> bool:
    return os.getenv("AI_DIGEST", "1").strip().lower() not in {"0", "false", "no", "off"}


def enabled(chat_id: int) -> bool:
    return _enabled.get(chat_id, globally_enabled())


def set_enabled(chat_id: int, value: bool) -> None:
    _enabled[chat_id] = value


def manual_allowed(chat_id: int, now: float | None = None) -> bool:
    now = time.time() if now is None else now
    if now - _last_manual.get(chat_id, 0.0) < COOLDOWN:
        return False
    _last_manual[chat_id] = now
    return True


def _name(row: dict) -> str:
    return str(row.get("source_display_name") or row.get("full_name") or row.get("telegram_username")
               or row.get("minecraft_nickname") or row.get("tg_id") or "аноним")


async def gather(chat_id: int) -> dict:
    """All facts the digest may mention. Every source is optional: a failing one is simply absent."""
    facts: dict = {}
    try:
        facts["online"] = _TAG.sub("", await live._online())
    except Exception as exc:
        logger.debug("digest online failed: %s", exc)
    top = await bot_chat_top(chat_id, 1, 3)
    if not top.error and isinstance(top.data, list):
        facts["top"] = [{"name": _name(r), "messages": int(r.get("messages") or 0)} for r in top.data if isinstance(r, dict)]
    total = await bot_chat_top_total(chat_id, 1)
    if not total.error:
        try:
            facts["messages_today"] = int(total.data or 0)
        except (TypeError, ValueError):
            pass
    if config.OWNER_TG_ID:
        events = await bot_list_events(config.OWNER_TG_ID, 5)
        if not events.error and isinstance(events.data, list):
            facts["events"] = [{"title": str(r.get("title") or "")[:80], "starts_at": str(r.get("starts_at") or "")[:16]}
                               for r in events.data if isinstance(r, dict) and r.get("title")][:3]
    return facts


def has_news(facts: dict) -> bool:
    return bool(facts.get("messages_today") or facts.get("events"))


def template(facts: dict) -> str:
    lines = ["📰 Итоги дня в PRISMA"]
    if facts.get("online"):
        lines.append(facts["online"].replace("\n", " · "))
    if facts.get("messages_today") is not None:
        lines.append(f"💬 Сообщений в чате за сутки: {facts['messages_today']}")
    if facts.get("top"):
        lines.append("🏆 Самые активные: " + ", ".join(f"{t['name']} ({t['messages']})" for t in facts["top"]))
    if facts.get("events"):
        lines.append("🎯 Ближайшие ивенты: " + "; ".join(f"{e['title']} — {e['starts_at']}" for e in facts["events"]))
    lines.append("Хорошего вечера! Вопросы — к PRISMA_AI: просто напишите «Призма, …».")
    return "\n".join(lines)


_SYSTEM = (
    "Ты — PRISMA_AI и пишешь вечерний дайджест Minecraft-чата PRISMA. Используй ТОЛЬКО факты из блока ФАКТЫ: ничего не добавляй "
    "и не выдумывай (ни цифр, ни имён, ни событий). Если какого-то факта нет — просто не упоминай. 5–8 коротких строк, живо, "
    "с эмодзи, по-русски; начни с заголовка «📰 Итоги дня в PRISMA». В конце одна бодрая фраза и подсказка, что можно написать "
    "«Призма, …». Выводи только сам текст дайджеста, без рассуждений."
)
_ADULT = " РЕЖИМ 18+: можно мат, чёрный юмор и подколы участников, тон дерзкий; факты по-прежнему только из блока."


async def build(chat_id: int, facts: dict | None = None) -> str:
    facts = facts if facts is not None else await gather(chat_id)
    if is_configured("user"):
        system = _SYSTEM + (_ADULT if ambient.adult(chat_id) else "")
        try:
            message = await chat_with_fallback(
                [{"role": "system", "content": system}, {"role": "user", "content": f"ФАКТЫ:\n{facts}"}],
                role="user", max_tokens=900, timeout=40, temperature=0.8 if ambient.adult(chat_id) else 0.5)
            text = sanitize.clean(str(message.get("content") or ""))
            if text:
                return strip_markdown(text)
        except AIError as exc:
            logger.info("digest model failed, using the template: %s", exc)
    return template(facts)


async def run_digest_worker(bot: Bot, stop_event: asyncio.Event):
    if not globally_enabled():
        logger.info("Digest disabled: AI_DIGEST=0")
        return
    # A restart in the evening must not repost: if today's hour has already passed, wait for tomorrow.
    now = datetime.now(TZ)
    last_sent_on = now.date() if now.hour >= HOUR else None
    while not stop_event.is_set():
        now = datetime.now(TZ)
        if now.hour >= HOUR and last_sent_on != now.date():
            last_sent_on = now.date()  # set first: a failure must not turn into a retry storm
            try:
                chat = await bot_get_community_chat_id()
                chat_id = int(chat.data) if not chat.error and chat.data else 0
                if chat_id and enabled(chat_id):
                    facts = await gather(chat_id)
                    if has_news(facts):
                        await bot.send_message(chat_id, await build(chat_id, facts), disable_notification=True)
            except Exception:
                logger.exception("Digest failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=600)
        except asyncio.TimeoutError:
            pass
