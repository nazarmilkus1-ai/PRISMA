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


def _status_line(g: dict) -> str:
    health = g.get("health_pct")
    verdict = (g.get("review") or {}).get("verdict")
    if verdict == "BLOCK":
        return "🔴 Второй ИИ против слияния — лучше не сливать"
    if health is None:
        return "⏳ Тесты ещё не запускались"
    if health < 100:
        return f"⏳ Тесты ещё идут или не все прошли ({health}%) — кнопка пока может отказать"
    if verdict == "RISKS":
        return "🟡 Тесты прошли, но второй ИИ видит риски — посмотрите описание"
    return "🟢 Тесты прошли — можно сливать"


async def _live_link(g: dict) -> str:
    branch = g.get("branch")
    url = await github.preview_url(branch) if branch else None
    if url:
        return f"👀 Посмотреть вживую: {url}"
    return "🤖 Это изменение внутри бота — заработает после слияния (≈3 минуты)"


async def render_waiting(g: dict) -> str:
    review = g.get("review") or {}
    explain = review.get("plain") or g.get("expected") or ""
    lines = [f"<b>{html.escape(str(g.get('title')))}</b>"]
    if explain:
        lines.append(f"💡 {_plain(explain, 300)}")
    lines.append(_status_line(g))
    if review.get("verdict") == "RISKS" and review.get("notes"):
        lines.append(f"⚠️ {_plain(review['notes'], 200)}")
    lines.append(await _live_link(g))
    lines.append(f"🔗 Подробности: {_pr_url(g.get('pr_number'))}")
    return "\n".join(lines)


def render_goal(g: dict) -> str:
    lines = [f"<b>{html.escape(str(g.get('title')))}</b>", f"{bar(g.get('progress_pct'))}"]
    if g.get("expected"):
        lines.append(f"🎁 {_plain(g['expected'], 240)}")
    return "\n".join(lines)


def _dedupe(items: list[str], limit: int = 3) -> list[str]:
    out, seen = [], set()
    for text in items:
        key = " ".join(text.lower().split()[:5])
        if text and key not in seen:
            seen.add(key)
            out.append(text)
    return out[:limit]


async def build() -> tuple[str, InlineKeyboardMarkup | None]:
    state = (await rpc.bot_agent_state_get()).data or {}
    journal = [j for j in ((await rpc.bot_agent_journal_recent(30, "cycle")).data or []) if isinstance(j, dict)]
    skip = ("цикл без итога", "цикл: изучал", "пауза")
    done = _dedupe([_plain(j.get("body"), 220) for j in journal if not str(j.get("body") or "").lower().startswith(skip)], 3)
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    waiting = [g for g in ((await rpc.bot_agent_goals_list("done", 20)).data or []) if g.get("pr_number") and not g.get("merged_at")][:4]
    paused = bool(state.get("paused"))
    parts = ["⏸ <b>Агент на паузе</b> — ничего не делает, пока не нажмёте «Продолжить»" if paused else f"🤖 <b>Отчёт агента</b> · {hhmm()}"]
    parts.append("🛠 <b>Что делал</b>\n" + ("\n".join(f"• {d}" for d in done) if done else "• пока изучаю проект, новостей нет"))
    nxt = state.get("next_step")
    if nxt and not paused:
        parts.append(f"🔜 <b>Дальше</b>\n{_plain(nxt, 220)}")
    if active:
        parts.append("⚙️ <b>Сейчас в работе</b>\n" + render_goal(active[0]))
    rows = []
    if waiting:
        cards = []
        for i, g in enumerate(waiting, 1):
            cards.append(f"{i}️⃣ " + await render_waiting(g))
            rows.append([InlineKeyboardButton(text=f"✅ Слить: {str(g.get('title'))[:28]}", callback_data=f"agent:merge:{g['pr_number']}")])
        parts.append(f"✅ <b>Готово — ждёт вашего решения ({len(waiting)})</b>\n\n" + "\n\n".join(cards))
    rows.append([InlineKeyboardButton(text="▶ Продолжить" if paused else "⏸ Пауза", callback_data="agent:toggle")])
    text = "\n\n".join(parts)
    if len(text) > 3900:
        text = text[:3850] + "…"
    return text, InlineKeyboardMarkup(inline_keyboard=rows)


async def send_hourly(bot) -> None:
    text, markup = await build()
    await post(bot, text, markup)
