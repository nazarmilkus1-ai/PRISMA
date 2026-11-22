"""Hourly report and the one merge button, posted only into the agent's own topic."""
from __future__ import annotations

import html
import logging
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc

from . import config, github

logger = logging.getLogger(__name__)
_VERDICT = {"OK": "🟢 Второй ИИ проверил: всё ок", "RISKS": "🟡 Второй ИИ: есть риски", "BLOCK": "🔴 Второй ИИ: блокирует"}


async def post(bot, text: str, markup: InlineKeyboardMarkup | None = None):
    try:
        return await bot.send_message(config.CHAT_ID, text[:4000], message_thread_id=config.THREAD_ID, parse_mode="HTML",
                                      reply_markup=markup, disable_web_page_preview=True)
    except Exception as exc:
        logger.warning("agent post failed: %s", exc)
        return None


KYIV = ZoneInfo("Europe/Kyiv")


def hhmm(dt: datetime | None = None) -> str:
    return (dt or datetime.now(KYIV)).astimezone(KYIV).strftime("%H:%M")


async def live(bot, text: str) -> None:
    """One status message that is edited in place, so the process is visible without spamming the topic."""
    state = (await rpc.bot_agent_state_get()).data or {}
    mid = state.get("live_msg_id")
    if mid:
        try:
            await bot.edit_message_text(text[:4000], chat_id=config.CHAT_ID, message_id=mid, parse_mode="HTML")
            return
        except Exception as exc:
            if "not modified" in str(exc).lower():
                return
    sent = await post(bot, text)
    if sent:
        await rpc.bot_agent_state_patch({"live_msg_id": sent.message_id})


def live_text(ctx, total: int, status: str = "⚙️ Работаю") -> str:
    goal = ctx.goal or {}
    lines = [f"🛰 <b>Агент прямо сейчас</b>", f"{status} · шаг {ctx.step}/{total} · {hhmm()}"]
    if goal:
        lines.append(f"🎯 {html.escape(str(goal.get('title') or ''))[:120]}")
        lines.append(f"📊 Готово: {bar(goal.get('progress_pct'))}")
    recent = ctx.actions[-6:]
    if recent:
        lines += ["", "<b>Что делал:</b>"] + [f"▸ {html.escape(a)}" for a in recent]
    return "\n".join(lines)


async def live_progress(ctx) -> None:
    if time.monotonic() - ctx.live_at < 4:
        return
    ctx.live_at = time.monotonic()
    try:
        await live(ctx.bot, live_text(ctx, config.MAX_STEPS))
    except Exception as exc:
        logger.debug("live update skipped: %s", exc)


def bar(pct: int) -> str:
    pct = max(0, min(100, int(pct or 0)))
    full = round(pct / 10)
    return "▰" * full + "▱" * (10 - full) + f" {pct}%"


def _pr_url(n) -> str:
    repo, _ = github._repo()
    return f"https://github.com/{repo}/pull/{n}" if repo and n else ""


def _plain(text: str, n: int = 260) -> str:
    return html.escape(" ".join(str(text or "").split())[:n])


def render_goal(g: dict) -> str:
    lines = [f"<b>{html.escape(str(g.get('title')))}</b>", f"📊 Готово: {bar(g.get('progress_pct'))}"]
    lines.append(f"🩺 Работает: {bar(g.get('health_pct'))}" if g.get("health_pct") is not None else "🩺 Работает: проверок ещё нет")
    if g.get("expected"):
        lines.append(f"🎁 Что получится: {_plain(g['expected'], 280)}")
    if g.get("pr_number"):
        lines.append(f"🔗 {_pr_url(g['pr_number'])}")
    review = g.get("review") or {}
    if review.get("verdict"):
        lines.append(f"🔍 {_VERDICT.get(review['verdict'], review['verdict'])}: {_plain(review.get('notes'), 240)}")
    if g.get("branch"):
        lines.append(f"🌿 <code>{html.escape(str(g['branch']))}</code>")
    return "\n".join(lines)


_GLOSSARY = ("ℹ️ <i>«Готово» — сколько задуманной работы сделано. «Работает» — сколько автопроверок (CI) проходит: "
             "100% = можно сливать.</i>")


async def build() -> tuple[str, InlineKeyboardMarkup | None]:
    state = (await rpc.bot_agent_state_get()).data or {}
    journal = [j for j in ((await rpc.bot_agent_journal_recent(30, "cycle")).data or []) if isinstance(j, dict)]
    useful = [j for j in journal if str(j.get("body")) not in {"пауза"}][:5]
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    waiting = [g for g in ((await rpc.bot_agent_goals_list("done", 10)).data or []) if g.get("pr_number") and not g.get("merged_at")][:3]
    mem = (await rpc.bot_agent_mem_count()).data or 0
    paused = bool(state.get("paused"))
    parts = ["⏸ <b>Агент на паузе</b> — ничего не делает, пока не нажмёте «Продолжить»" if paused else
             f"🤖 <b>Отчёт PRISMA-агента</b> · {hhmm()}"]
    parts.append("━━━━━━━━━━━━━━")
    parts.append("🛠 <b>Что сделал за это время</b>\n" + ("\n".join(f"• {_plain(j.get('body'))}" for j in useful) if useful else "• пока только разбираюсь с проектом"))
    nxt = state.get("next_step")
    if nxt and not paused:
        parts.append(f"🔜 <b>Что дальше</b>\n{_plain(nxt)}")
    parts.append("━━━━━━━━━━━━━━")
    if active:
        parts.append("🎯 <b>Сейчас в работе</b>\n" + render_goal(active[0]))
    else:
        parts.append("🎯 <b>Сейчас в работе</b>\nнового задания нет — выберу сам в следующем цикле")
    rows = []
    for g in waiting:
        parts.append(f"✅ <b>Готово, ждёт вашей кнопки</b>\n" + render_goal(g))
        rows.append([InlineKeyboardButton(text=f"✅ Слить #{g['pr_number']}", callback_data=f"agent:merge:{g['pr_number']}")])
    parts.append("━━━━━━━━━━━━━━")
    parts.append(f"🧠 В памяти заметок: {mem} · цикл каждые {config.CYCLE_SECONDS // 60} мин, отчёт раз в {config.REPORT_SECONDS // 3600} ч")
    parts.append(_GLOSSARY)
    rows.append([InlineKeyboardButton(text="▶ Продолжить" if paused else "⏸ Пауза", callback_data="agent:toggle")])
    return "\n\n".join(parts), InlineKeyboardMarkup(inline_keyboard=rows)


async def send_hourly(bot) -> None:
    text, markup = await build()
    await post(bot, text, markup)
