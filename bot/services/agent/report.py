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
        lines.append(f"🎯 {short(goal.get('title'), 100)}")
        if goal.get("expected"):
            lines.append(f"🧭 Собираюсь: {short(goal['expected'], 140)}")
        lines.append(bar(goal.get("progress_pct")))
    collapsed: list[list] = []
    for a in ctx.actions[-14:]:
        if collapsed and collapsed[-1][0] == a:
            collapsed[-1][1] += 1
        else:
            collapsed.append([a, 1])
    if collapsed:
        lines += ["", "<b>Что делал:</b>"] + [f"▸ {html.escape(a)}" + (f" ×{n}" if n > 1 else "") for a, n in collapsed[-6:]]
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
    from .brain import strip_tech
    return html.escape(strip_tech(" ".join(str(text or "").split()))[:n])


def short(text: str, n: int = 100) -> str:
    """Plain, single-line, cut at a word boundary."""
    from .brain import strip_tech
    clean = " ".join(strip_tech(str(text or "")).split())
    if len(clean) <= n:
        return html.escape(clean)
    return html.escape(clean[:n].rsplit(" ", 1)[0].rstrip(",;:- ") + "…")


def _status_line(g: dict) -> str:
    health = g.get("health_pct")
    verdict = (g.get("review") or {}).get("verdict")
    if verdict == "BLOCK":
        return "🔴 Второй ИИ против — лучше отклонить"
    if health is None:
        return "⏳ Тесты ещё не запускались"
    if health < 100:
        return f"⏳ Тесты идут или не все прошли ({health}%)"
    if verdict == "RISKS":
        return "🟡 Тесты прошли, но есть риски"
    return "🟢 Тесты прошли"


async def _live_link(g: dict) -> str:
    branch = g.get("branch")
    url = await github.preview_url(branch) if branch else None
    if url:
        return f"👀 Посмотреть вживую: {url}"
    return "🤖 Внутри бота — заработает через ≈3 минуты после «Принять»"


async def waiting_goals() -> list[dict]:
    goals = (await rpc.bot_agent_goals_list("done", 30)).data or []
    return sorted((g for g in goals if g.get("pr_number") and not g.get("merged_at")), key=lambda g: g["pr_number"])[:8]


def _summary(g: dict) -> str:
    review = g.get("review") or {}
    return short(review.get("plain") or g.get("expected") or g.get("title"), 90)


async def build() -> tuple[str, InlineKeyboardMarkup]:
    state = (await rpc.bot_agent_state_get()).data or {}
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    waiting = await waiting_goals()
    paused = bool(state.get("paused"))
    parts = [("⏸ <b>Агент на паузе</b>" if paused else "🤖 <b>Агент</b>") + f" · {hhmm()}"]
    if active:
        g = active[0]
        now = f"<b>{short(g.get('title'), 80)}</b>"
        if g.get("expected"):
            now += f"\n🧭 {short(g['expected'], 110)}"
        parts.append(f"🎯 <b>Сейчас</b>\n{now}\n{bar(g.get('progress_pct'))}")
    elif waiting and len(waiting) >= 3:
        parts.append("🎯 <b>Сейчас</b>\n😴 Жду ваших решений по готовым задачам")
    else:
        parts.append("🎯 <b>Сейчас</b>\nВыбираю следующую задачу")
    if waiting:
        lines = [f"№{i} · {_summary(g)}" for i, g in enumerate(waiting, 1)]
        parts.append("✅ <b>Готово — ждёт вас</b>\n" + "\n".join(lines) + "\n<i>Нажмите номер, чтобы посмотреть</i>")
    nxt = state.get("next_step")
    if nxt and not paused:
        parts.append(f"🔜 {short(nxt, 100)}")
    rows = []
    if waiting:
        rows.append([InlineKeyboardButton(text=f"№{i}", callback_data=f"agent:open:{g['pr_number']}") for i, g in enumerate(waiting, 1)])
    rows.append([InlineKeyboardButton(text="▶ Продолжить" if paused else "⏸ Пауза", callback_data="agent:toggle")])
    return "\n\n".join(parts), InlineKeyboardMarkup(inline_keyboard=rows)


async def detail(pr_number: int) -> tuple[str, InlineKeyboardMarkup]:
    waiting = await waiting_goals()
    pos = next((i for i, g in enumerate(waiting, 1) if g["pr_number"] == pr_number), None)
    g = next((g for g in waiting if g["pr_number"] == pr_number), None)
    back = [InlineKeyboardButton(text="← К списку", callback_data="agent:list")]
    if not g:
        return "Эта задача уже обработана.", InlineKeyboardMarkup(inline_keyboard=[back])
    review = g.get("review") or {}
    lines = [f"<b>№{pos} · {short(g.get('title'), 80)}</b>", f"💡 {short(review.get('plain') or g.get('expected'), 240)}", _status_line(g)]
    if review.get("verdict") == "RISKS" and review.get("notes"):
        lines.append(f"⚠️ {short(review['notes'], 140)}")
    lines.append(await _live_link(g))
    markup = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="✅ Принять", callback_data=f"agent:merge:{pr_number}"),
         InlineKeyboardButton(text="❌ Отклонить", callback_data=f"agent:reject:{pr_number}")], back])
    return "\n".join(lines), markup


async def send_hourly(bot) -> None:
    text, markup = await build()
    await post(bot, text, markup)
