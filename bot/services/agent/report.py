"""Hourly report and the one merge button, posted only into the agent's own topic."""
from __future__ import annotations

import html
import logging

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc

from . import config, github

logger = logging.getLogger(__name__)
_VERDICT = {"OK": "🟢 ревьюер: ок", "RISKS": "🟡 ревьюер: есть риски", "BLOCK": "🔴 ревьюер: блок"}


async def post(bot, text: str, markup: InlineKeyboardMarkup | None = None):
    try:
        return await bot.send_message(config.CHAT_ID, text[:4000], message_thread_id=config.THREAD_ID, parse_mode="HTML",
                                      reply_markup=markup, disable_web_page_preview=True)
    except Exception as exc:
        logger.warning("agent post failed: %s", exc)
        return None


def bar(pct: int) -> str:
    pct = max(0, min(100, int(pct or 0)))
    full = round(pct / 10)
    return "▰" * full + "▱" * (10 - full) + f" {pct}%"


def _pr_url(n) -> str:
    repo, _ = github._repo()
    return f"https://github.com/{repo}/pull/{n}" if repo and n else ""


def render_goal(g: dict) -> str:
    lines = [f"🎯 <b>{html.escape(str(g.get('title')))}</b>",
             f"Готово: {bar(g.get('progress_pct'))}",
             f"Работает: {bar(g.get('health_pct'))}" if g.get("health_pct") is not None else "Работает: проверок ещё нет"]
    if g.get("expected"):
        lines.append(f"Ожидаем: {html.escape(str(g['expected'])[:300])}")
    if g.get("branch"):
        lines.append(f"Ветка: <code>{html.escape(str(g['branch']))}</code>")
    if g.get("pr_number"):
        lines.append(f"PR: {_pr_url(g['pr_number'])}")
    review = g.get("review") or {}
    if review.get("verdict"):
        lines.append(f"{_VERDICT.get(review['verdict'], review['verdict'])}: {html.escape(str(review.get('notes') or '')[:300])}")
    return "\n".join(lines)


async def build() -> tuple[str, InlineKeyboardMarkup | None]:
    state = (await rpc.bot_agent_state_get()).data or {}
    journal = [j for j in ((await rpc.bot_agent_journal_recent(12, "cycle")).data or []) if isinstance(j, dict)][:8]
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    waiting = [g for g in ((await rpc.bot_agent_goals_list("done", 10)).data or []) if g.get("pr_number") and not g.get("merged_at")][:3]
    head = "⏸ <b>Агент на паузе</b>\n" if state.get("paused") else "🤖 <b>Часовой отчёт PRISMA-агента</b>\n"
    parts = [head]
    done = [html.escape(str(j.get("body"))[:300]) for j in journal if str(j.get("body")) not in {"пауза"}]
    parts.append("<b>Что сделал:</b>\n" + ("\n".join(f"• {d}" for d in done[:5]) if done else "• пока ничего (ищу, что улучшить)"))
    if active:
        parts.append(render_goal(active[0]))
    else:
        parts.append("🎯 Активной цели нет — выберу следующую сам.")
    rows = []
    for g in waiting:
        parts.append("✅ <b>Ждёт слияния</b>\n" + render_goal(g))
        rows.append([InlineKeyboardButton(text=f"✅ Слить #{g['pr_number']}", callback_data=f"agent:merge:{g['pr_number']}")])
    rows.append([InlineKeyboardButton(text="▶ Продолжить" if state.get("paused") else "⏸ Пауза", callback_data="agent:toggle")])
    return "\n\n".join(parts), InlineKeyboardMarkup(inline_keyboard=rows)


async def send_hourly(bot) -> None:
    text, markup = await build()
    await post(bot, text, markup)
