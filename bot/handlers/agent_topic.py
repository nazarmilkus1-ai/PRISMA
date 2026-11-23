"""The agent's only home: one Telegram topic. Everything else in the chat (and every other chat) is ignored here."""
from __future__ import annotations

import html
import logging
import time

from aiogram import F, Router, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc
from services.agent import config, merge, report
from utils.permissions import staff_context

logger = logging.getLogger(__name__)
router = Router(name="agent_topic")

_in_topic = (F.chat.id == config.CHAT_ID) & (F.message_thread_id == config.THREAD_ID)
_last_ack: dict[int, float] = {}


def _addressed(message: types.Message, bot_id: int, username: str) -> bool:
    reply = message.reply_to_message
    if reply and reply.from_user and reply.from_user.id == bot_id:
        return True
    text = (message.text or "").lower()
    return bool(username) and f"@{username.lower()}" in text


@router.message(Command("agent_pause", "agent_resume", "agent_status", "agent_report"), _in_topic)
async def admin_commands(message: types.Message):
    ctx = await staff_context(message.from_user.id)
    if not ctx.get("is_staff"):
        return
    cmd = (message.text or "").split()[0].lstrip("/").split("@")[0]
    if cmd == "agent_pause":
        await rpc.bot_agent_state_patch({"paused": True})
        await message.reply("⏸ Пауза. Продолжить: /agent_resume")
    elif cmd == "agent_resume":
        await rpc.bot_agent_state_patch({"paused": False})
        await message.reply("▶ Работаю дальше.")
    else:
        text, markup = await report.build()
        await message.reply(text, parse_mode="HTML", reply_markup=markup, disable_web_page_preview=True)


@router.message(_in_topic, F.text, ~F.from_user.is_bot)
async def ingest(message: types.Message):
    """Every human message is remembered for the agent; admin messages carry priority, others are only suggestions."""
    ctx = await staff_context(message.from_user.id)
    user = message.from_user
    await rpc.bot_agent_inbox_add(user.id, user.username or user.full_name, bool(ctx.get("is_staff")), (message.text or "")[:1500], message.message_id)
    text = (message.text or "").strip()
    if ctx.get("is_staff") and len(text) >= 12 and not text.startswith("/"):
        # What admins say is remembered right away, so the agent keeps their wishes even if it forgets the chat.
        await rpc.bot_agent_mem_add("user", f"Админ @{user.username or user.full_name} написал в топике: {text[:600]}", [], 4, False)
    me = await message.bot.me()
    if _addressed(message, me.id, me.username or "") and time.monotonic() - _last_ack.get(user.id, 0) > 60:
        _last_ack[user.id] = time.monotonic()
        who = "приоритетно" if ctx.get("is_staff") else "как предложение"
        await message.reply(f"👌 Принял, учту {who} в ближайшем цикле (до 10 минут).")


async def _show(callback: types.CallbackQuery, text: str, markup: InlineKeyboardMarkup) -> None:
    try:
        await callback.message.edit_text(text, parse_mode="HTML", reply_markup=markup, disable_web_page_preview=True)
    except Exception as exc:  # "message is not modified" and the like
        logger.debug("agent card not edited: %s", exc)


@router.callback_query(F.data.startswith("agent:"))
async def buttons(callback: types.CallbackQuery):
    msg = callback.message
    if not msg or msg.chat.id != config.CHAT_ID or msg.message_thread_id != config.THREAD_ID:
        await callback.answer()
        return
    ctx = await staff_context(callback.from_user.id)
    if not ctx.get("is_staff"):
        await callback.answer("Это только для админов.", show_alert=True)
        return
    perms = ctx.get("permissions") or []
    parts = (callback.data or "").split(":")
    action = parts[1] if len(parts) > 1 else ""
    number = int(parts[2]) if len(parts) == 3 and parts[2].isdigit() else 0
    if action == "toggle":
        paused = bool(((await rpc.bot_agent_state_get()).data or {}).get("paused"))
        await rpc.bot_agent_state_patch({"paused": not paused})
        await callback.answer("Продолжаю" if paused else "Пауза")
        text, markup = await report.build()
        await _show(callback, text, markup)
        return
    if action == "list":
        await callback.answer()
        text, markup = await report.build()
        await _show(callback, text, markup)
        return
    if action == "open" and number:
        await callback.answer()
        text, markup = await report.detail(number)
        await _show(callback, text, markup)
        return
    if action in {"merge", "force", "reject"} and number:
        if not merge.can_merge(callback.from_user.id, perms):
            await callback.answer("Принимать и отклонять могут только главные админы.", show_alert=True)
            return
        who = html.escape(callback.from_user.full_name)
        if action == "reject":
            await callback.answer("Отклоняю…")
            ok, text = await merge.reject(number)
            await report.post(callback.bot, f"❌ Задача отклонена — {who}" if ok else f"⛔ {html.escape(text)}")
        else:
            await callback.answer("Проверяю и принимаю…")
            top = bool({"*", "admin.manage"} & set(perms))
            ok, text = await merge.do_merge(number, owner=top, override=(action == "force"))
            if ok:
                await report.post(callback.bot, f"✅ Задача принята — {who}. Заработает через ≈3 минуты.")
            else:
                markup = None
                if top and "BLOCK" in text:
                    markup = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="Принять всё равно", callback_data=f"agent:force:{number}")]])
                await report.post(callback.bot, f"⛔ Не принято: {html.escape(text)}", markup)
        text, markup = await report.build()  # the queue renumbers itself: №2 becomes №1
        await _show(callback, text, markup)
        return
    await callback.answer()
