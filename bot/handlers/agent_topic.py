"""The agent's only home: one Telegram topic. Everything else in the chat (and every other chat) is ignored here."""
from __future__ import annotations

import html
import logging
import time

from aiogram import F, Router, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc
from services.agent import autopilot, chat, config, jobs, merge, report
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


def _who(user: types.User) -> str:
    return f"@{user.username}" if user.username else user.full_name


async def _task_reply(goal: dict, note: str) -> str:
    title = html.escape(str(goal.get("title") or ""))
    if note:
        return f"ℹ️ {html.escape(note)}\n📝 <b>{title}</b>"
    queue = await jobs.queued()
    pos = next((i for i, g in enumerate(queue, 1) if g.get("id") == goal.get("id")), 1)
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    soon = not active or (active[0].get("source") != "admin" and not active[0].get("pr_number") and int(active[0].get("progress_pct") or 0) <= 20)
    when = "Начну в течение минуты." if soon and pos == 1 else f"Я в работе над другим — ваша задача №{pos} в очереди, возьму сразу после."
    auto = autopilot.enabled((await rpc.bot_agent_state_get()).data or {})
    tail = "Когда будет готово и тесты пройдут, сам приму и сообщу." if auto else "Когда будет готово, пришлю карточку с кнопкой «Принять»."
    return f"📝 Принял задачу: <b>{title}</b>\n{when} {tail}"


@router.message(Command("agent_pause", "agent_resume", "agent_status", "agent_report", "agent", "agent_help", "agent_auto", "task", "ideas"), _in_topic)
async def admin_commands(message: types.Message):
    cmd = (message.text or "").split()[0].lstrip("/").split("@")[0]
    if cmd == "agent_help":
        await message.reply(report.HELP, parse_mode="HTML", disable_web_page_preview=True)
        return
    ctx = await staff_context(message.from_user.id)
    if not ctx.get("is_staff"):
        if cmd == "task":
            await message.reply("Задачи ставят админы. Напишите свою идею обычным сообщением — я запишу её как предложение.")
        return
    if cmd == "agent_pause":
        await rpc.bot_agent_state_patch({"paused": True})
        await message.reply("⏸ Пауза. Вернуть работу: /agent_resume или кнопка «▶ Продолжить».")
    elif cmd == "agent_resume":
        await rpc.bot_agent_state_patch({"paused": False, "ai_wait_until": None})  # also asks the AI again if it was waiting for its daily limit
        await jobs.wake()
        await message.reply("▶ Работаю дальше — следующий цикл начнётся в течение минуты.")
    elif cmd == "agent_auto":
        arg = ((message.text or "").split(maxsplit=1) + [""])[1].strip().lower()
        state = (await rpc.bot_agent_state_get()).data or {}
        if arg and not merge.can_merge(message.from_user.id, ctx.get("permissions") or []):
            await message.reply("Включать и выключать автослияние могут только главные админы.")
        elif arg in {"off", "0", "выкл", "нет"}:
            await rpc.bot_agent_state_patch({"auto_merge": False})
            await message.reply("🛑 Автослияние выключено: готовые задачи будут ждать вашего «Принять». Включить: /agent_auto on")
        elif arg in {"on", "1", "вкл", "да"}:
            await rpc.bot_agent_state_patch({"auto_merge": True})
            await message.reply("🚀 Автослияние включено: я сам принимаю свои задачи, когда все автотесты зелёные.")
        else:
            now = "включено" if autopilot.enabled(state) else "выключено"
            await message.reply(f"Автослияние сейчас {now}. Команды: /agent_auto on · /agent_auto off")
    elif cmd == "task":
        parts = (message.text or "").split(maxsplit=1)
        if len(parts) < 2 or not parts[1].strip():
            await message.reply("Напишите задачу после команды, например:\n<code>/task добавить в меню кнопку «Правила»</code>", parse_mode="HTML")
            return
        goal, note = await jobs.add_task(parts[1], _who(message.from_user))
        if not goal:
            await message.reply(html.escape(note))
            return
        if not note:
            await jobs.wake()
        await message.reply(await _task_reply(goal, note), parse_mode="HTML", reply_markup=report.panel())
    elif cmd == "ideas":
        text, markup = await report.ideas_view()
        await message.reply(text, parse_mode="HTML", reply_markup=markup, disable_web_page_preview=True)
    else:
        text, markup = await report.build()
        await message.reply(text, parse_mode="HTML", reply_markup=markup, disable_web_page_preview=True)


@router.message(_in_topic, F.text, ~F.from_user.is_bot)
async def ingest(message: types.Message):
    """Every human message is remembered for the agent; admin messages carry priority, others are only suggestions.
    When someone talks to the agent (reply / mention) or an admin asks a question, it answers in plain words — and an admin's
    request for work becomes a queued task right away."""
    ctx = await staff_context(message.from_user.id)
    staff = bool(ctx.get("is_staff"))
    user = message.from_user
    text = (message.text or "").strip()
    await rpc.bot_agent_inbox_add(user.id, user.username or user.full_name, staff, text[:1500], message.message_id)
    if staff and len(text) >= 12 and not text.startswith("/") and not text.endswith("?"):
        # What admins say is remembered right away, so the agent keeps their wishes even if it forgets the chat.
        await rpc.bot_agent_mem_add("user", f"Админ @{user.username or user.full_name} написал в топике: {text[:600]}", [], 4, False)
    me = await message.bot.me()
    asked = (staff and text.endswith("?")) or _addressed(message, me.id, me.username or "")
    gap = 20 if staff else 60
    last = _last_ack.get(user.id)  # None for a first message: monotonic() can be tiny right after a host boot
    if not asked or (last is not None and time.monotonic() - last <= gap):
        return
    _last_ack[user.id] = time.monotonic()
    out = await chat.answer(text.replace(f"@{me.username}", "").strip() if me.username else text, _who(user), staff)
    if not out:
        who = "приоритетно" if staff else "как предложение"
        await message.reply(f"👌 Принял, учту {who} в ближайшем цикле (до {jobs.cycle_minutes()} минут).")
        return
    reply, task = out
    answer = html.escape(reply)
    if task:
        goal, note = await jobs.add_task(task, _who(user))
        if goal and not note:
            await jobs.wake()
            answer += f"\n\n📝 Поставил задачу: <b>{html.escape(str(goal.get('title') or ''))}</b>. Начну в течение минуты."
        elif goal:
            answer += f"\n\nℹ️ {html.escape(note)}"
    await message.reply(answer, parse_mode="HTML", reply_markup=report.panel())


async def _show(callback: types.CallbackQuery, text: str, markup: InlineKeyboardMarkup) -> None:
    """Edit the message the button was pressed on. The live status itself is never overwritten: its buttons open one shared panel message."""
    msg = callback.message
    state = (await rpc.bot_agent_state_get()).data or {}
    if msg and msg.message_id == state.get("live_msg_id"):
        panel_id = state.get("panel_msg_id")
        if panel_id:
            try:
                await callback.bot.edit_message_text(text, chat_id=config.CHAT_ID, message_id=panel_id, parse_mode="HTML",
                                                     reply_markup=markup, disable_web_page_preview=True)
                return
            except Exception as exc:
                if "not modified" in str(exc).lower():
                    return
        sent = await report.post(callback.bot, text, markup)
        if sent:
            await rpc.bot_agent_state_patch({"panel_msg_id": sent.message_id})
        return
    try:
        await msg.edit_text(text, parse_mode="HTML", reply_markup=markup, disable_web_page_preview=True)
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
        if paused:
            await jobs.wake()
        if msg.message_id == ((await rpc.bot_agent_state_get()).data or {}).get("live_msg_id"):
            try:
                await msg.edit_reply_markup(reply_markup=report.panel(not paused))  # only the button flips; the live text stays
            except Exception as exc:
                logger.debug("live buttons not edited: %s", exc)
            return
        text, markup = await report.build()
        await _show(callback, text, markup)
        return
    if action == "help":
        await callback.answer()
        await _show(callback, report.HELP, InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="← К списку", callback_data="agent:list")]]))
        return
    if action == "ideas":
        await callback.answer()
        text, markup = await report.ideas_view()
        await _show(callback, text, markup)
        return
    if action in {"idea", "noidea"} and number:
        if action == "idea":
            goal, note = await jobs.take_idea(number, _who(callback.from_user))
            if goal and not note:
                await jobs.wake()
            await callback.answer(note or "▶ Беру в работу — начну в течение минуты", show_alert=bool(note))
        else:
            await jobs.drop_idea(number)
            await callback.answer("✖ Убрал")
        text, markup = await report.ideas_view()
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
    if action == "revert" and number:
        if not merge.can_merge(callback.from_user.id, perms):
            await callback.answer("Откатывать могут только главные админы.", show_alert=True)
            return
        found = await merge.revert_task(number)
        if not found:
            await callback.answer("Не могу откатить автоматически: нет данных о слиянии. Попросите меня задачей.", show_alert=True)
            return
        title, text = found
        goal, note = await jobs.add_task(text, _who(callback.from_user), source="admin", title=title)
        if goal and not note:
            await jobs.wake()
        await callback.answer(note or "↩ Откатываю: сделаю отдельную задачу и пришлю результат", show_alert=bool(note))
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
