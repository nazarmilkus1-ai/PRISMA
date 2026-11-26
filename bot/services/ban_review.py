"""Bans last 30 days; afterwards the player is NOT let back automatically.

When a ban's term ends the database moves it to "review" (users.ban_type = 'REVIEW', still banned). This worker tells
the admins once, with two buttons:
  ✅ Вернуть  → the ban is lifted (bot_lift_punishment), the player is unbanned in the community chat and the bot
                sends him an invitation link by itself;
  ⛔ Оставить → the ban stays until an admin lifts it (bot_ban_review_keep).
Anything not answered stays in the list `/bans`.
"""
from __future__ import annotations

import asyncio
import html
import logging
import time

from aiogram import Bot
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

import config
from db.rpc import bot_ban_review_claim, bot_get_community_chat_id
from utils.validation import Validation

logger = logging.getLogger(__name__)

POLL_SECONDS = 300
INVITE_TTL_SECONDS = 7 * 24 * 3600
CB_PREFIX = "banrev"


def card_text(row: dict) -> str:
    who = html.escape(str(row.get("nickname") or row.get("tg_id")))
    reason = html.escape(str(row.get("reason") or "—"))
    return (
        f"⏳ <b>Срок бана закончился</b>: {who} (<code>{row.get('tg_id')}</code>)\n"
        f"Причина бана: {reason}\n"
        "Игрок остаётся забаненным, пока вы не подтвердите возвращение."
    )


def keyboard(tg_id: int) -> InlineKeyboardMarkup:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для клавиатуры бана")
    if not valid:
        logger.warning("Invalid tg_id in keyboard: %s", error)
        # Return empty keyboard to prevent crash
        return InlineKeyboardMarkup(inline_keyboard=[])
    return InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text="✅ Вернуть", callback_data=f"{CB_PREFIX}:ok:{int(tg_id)}"),
        InlineKeyboardButton(text="⛔ Оставить бан", callback_data=f"{CB_PREFIX}:keep:{int(tg_id)}"),
    ]])


def parse_callback(data: str) -> tuple[str, int] | None:
    parts = (data or "").split(":")
    if len(parts) != 3 or parts[0] != CB_PREFIX or parts[1] not in {"ok", "keep"}:
        return None
    try:
        return parts[1], int(parts[2])
    except ValueError:
        return None


async def notify_admins(bot: Bot, rows: list[dict]) -> int:
    target = config.ADMIN_GROUP_ID or config.OWNER_TG_ID
    if not target:
        logger.warning("ban review: no admin chat configured; rows stay available through /bans")
        return 0
    sent = 0
    for row in rows:
        try:
            await bot.send_message(target, card_text(row), parse_mode="HTML", reply_markup=keyboard(int(row["tg_id"])))
            sent += 1
        except Exception:
            logger.exception("ban review notification failed for %s", row.get("tg_id"))
    return sent


async def invite_back(bot: Bot, tg_id: int) -> str:
    """Unban in the community chat and send the player an invitation. Returns a short status for the admins."""
    chat = await bot_get_community_chat_id()
    chat_id = chat.data if not chat.error and isinstance(chat.data, int) else None
    link = None
    if chat_id is not None:
        try:
            await bot.unban_chat_member(chat_id, tg_id, only_if_banned=True)
        except Exception:
            logger.exception("unban in community chat failed for %s", tg_id)
        try:
            created = await bot.create_chat_invite_link(
                chat_id, name="return after ban", member_limit=1, expire_date=int(time.time()) + INVITE_TTL_SECONDS)
            link = created.invite_link
        except Exception:
            logger.exception("invite link failed for %s", tg_id)
    text = "✅ Срок бана закончился, администратор подтвердил ваше возвращение в PRISMA."
    text += f"\nВот ссылка для входа в чат (действует 7 дней, один вход):\n{link}" if link else "\nЗайдите обратно в чат сообщества."
    try:
        await bot.send_message(tg_id, text, disable_web_page_preview=True)
    except Exception:
        return "бан снят; написать игроку не удалось" + (f", ссылка: {link}" if link else "")
    return "бан снят, игроку отправлено приглашение в чат" if link else "бан снят, игроку отправлено сообщение (ссылку создать не удалось)"


async def run_worker(bot: Bot, stop_event: asyncio.Event):
    while not stop_event.is_set():
        try:
            result = await bot_ban_review_claim(20)
            if not result.error and isinstance(result.data, list) and result.data:
                await notify_admins(bot, result.data)
        except Exception:
            logger.exception("ban review pass failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=POLL_SECONDS)
        except asyncio.TimeoutError:
            pass
