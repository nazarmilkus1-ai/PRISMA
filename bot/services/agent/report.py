"""Hourly report and the one merge button, posted only into the agent's own topic."""
from __future__ import annotations

import html
import logging
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc

from . import config, github, jobs
from .checks import norm_tasks

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
    markup = panel(bool(state.get("paused")))
    if mid:
        try:
            await bot.edit_message_text(text[:4000], chat_id=config.CHAT_ID, message_id=mid, parse_mode="HTML", reply_markup=markup)
            return
        except Exception as exc:
            if "not modified" in str(exc).lower():
                return
    sent = await post(bot, text, markup)
    if sent:
        await rpc.bot_agent_state_patch({"live_msg_id": sent.message_id})


def panel(paused: bool = False, refresh: bool = False) -> InlineKeyboardMarkup:
    """The same four buttons under the live status, the hourly report and every list: nothing to remember."""
    return InlineKeyboardMarkup(inline_keyboard=panel_rows(paused, refresh))


def panel_rows(paused: bool = False, refresh: bool = False) -> list[list[InlineKeyboardButton]]:
    return [[InlineKeyboardButton(text="🔄 Обновить" if refresh else "📋 Очередь", callback_data="agent:list"),
             InlineKeyboardButton(text="💡 Идеи", callback_data="agent:ideas")],
            [InlineKeyboardButton(text="▶ Продолжить" if paused else "⏸ Пауза", callback_data="agent:toggle"),
             InlineKeyboardButton(text="❓ Помощь", callback_data="agent:help")]]


def plan_lines(goal: dict, limit: int = 6) -> list[str]:
    tasks = norm_tasks(goal.get("tasks"))[:limit]
    first_open = next((i for i, t in enumerate(tasks) if not t["done"]), None)
    return [f"{'✅' if t['done'] else ('▶' if i == first_open else '▫')} {short(t['t'], 70)}" for i, t in enumerate(tasks)]


def live_text(ctx, total: int, status: str = "⚙️ Работаю") -> str:
    goal = ctx.goal or {}
    lines = [f"🛰 <b>Агент прямо сейчас</b>", f"{status} · шаг {ctx.step}/{total} · {hhmm()}"]
    if goal:
        lines.append(f"🎯 {short(goal.get('title'), 100)}")
        if goal.get("expected"):
            lines.append(f"🧭 Собираюсь: {short(goal['expected'], 140)}")
        lines.append(bar(goal.get("progress_pct")))
        plan = plan_lines(goal)
        if plan:
            lines += ["", "<b>План:</b>"] + plan
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
    meta = (g.get("review") or {}).get("ci") or {}
    if meta.get("failed") and not meta.get("pending"):
        return "🔴 Тесты не прошли — принять нельзя, я пытаюсь починить"
    if health is None or meta.get("total") == 0:
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


def plain_summary(g: dict) -> str:
    from .brain import strip_tech
    review = g.get("review") or {}
    return strip_tech(str(review.get("plain") or g.get("expected") or g.get("title") or ""))[:90]


def _merged_today(state: dict) -> int:
    entry = state.get("auto_merges") or {}
    return int(entry.get("n", 0)) if entry.get("day") == time.strftime("%Y-%m-%d") else 0


async def build() -> tuple[str, InlineKeyboardMarkup]:
    state = (await rpc.bot_agent_state_get()).data or {}
    active = (await rpc.bot_agent_goals_list("active", 1)).data or []
    waiting = await waiting_goals()
    queue = await jobs.queued()
    paused = bool(state.get("paused"))
    parts = [("⏸ <b>Агент на паузе</b>" if paused else "🤖 <b>Агент</b>") + f" · {hhmm()}"]
    if active:
        g = active[0]
        now = f"<b>{short(g.get('title'), 80)}</b>"
        if g.get("expected"):
            now += f"\n🧭 {short(g['expected'], 110)}"
        parts.append(f"🎯 <b>Сейчас</b>\n{now}\n{bar(g.get('progress_pct'))}")
    elif waiting and len(waiting) >= config.MAX_WAITING:
        parts.append("🎯 <b>Сейчас</b>\n💡 Ищу идеи и дорабатываю готовое, пока вы разбираете очередь")
    else:
        parts.append("🎯 <b>Сейчас</b>\nВыбираю следующую задачу")
    wait = float(state.get("ai_wait_until") or 0)
    if wait > time.time() and state.get("ai_quota"):
        parts.append(f"💤 Дневной лимит ИИ закончился — код пишу после ≈{hhmm(datetime.fromtimestamp(wait, KYIV))}. Слияния и починка PR идут как обычно.")
    if queue:
        parts.append("📝 <b>Ваши задачи — следующие</b>\n" + "\n".join(f"• {short(g.get('title'), 80)}" for g in queue[:3]))
    if waiting:
        numbered = [(i, g) for i, g in enumerate(waiting, 1)]
        if config.auto_merge_on(state):
            mine = [f"№{i} · {_summary(g)}" for i, g in numbered if not (g.get("review") or {}).get("manual")]
            yours = [f"№{i} · {_summary(g)}" for i, g in numbered if (g.get("review") or {}).get("manual")]
            if mine:
                parts.append("🚀 <b>Готово — сольётся само</b>\n" + "\n".join(mine) + "\n<i>Когда тесты зелёные — принимаю сам</i>")
            if yours:
                parts.append("🔔 <b>Нужно ваше решение</b>\n" + "\n".join(yours) + "\n<i>Это мой код, база, настройки или баны — без вас не сливаю</i>")
        else:
            lines = [f"№{i} · {_summary(g)}" for i, g in numbered]
            parts.append("✅ <b>Готово — ждёт вас</b>\n" + "\n".join(lines) + "\n<i>Нажмите номер, чтобы посмотреть</i>")
    merged_today = _merged_today(state)
    if merged_today:
        parts.append(f"🚀 Слито сегодня: {merged_today}")
    nxt = state.get("next_step")
    if nxt and not paused:
        parts.append(f"🔜 {short(nxt, 100)}")
    rows = []
    if waiting:
        rows.append([InlineKeyboardButton(text=f"№{i}", callback_data=f"agent:open:{g['pr_number']}") for i, g in enumerate(waiting, 1)])
    rows += panel_rows(paused, refresh=True)
    return "\n\n".join(parts), InlineKeyboardMarkup(inline_keyboard=rows)


async def ideas_view() -> tuple[str, InlineKeyboardMarkup]:
    items = await jobs.ideas(6)
    back = [InlineKeyboardButton(text="← К списку", callback_data="agent:list")]
    if not items:
        return ("💡 <b>Идеи</b>\nПока пусто: я копил их по ходу работы, но новых нет. Загляните позже или дайте задачу сами: "
                "<code>/task что сделать</code>"), InlineKeyboardMarkup(inline_keyboard=[back])
    lines = [f"{i}. {short(m.get('body'), 120)}" for i, m in enumerate(items, 1)]
    text = "💡 <b>Мои идеи</b>\n" + "\n".join(lines) + "\n\n<i>▶ — сделать это следующим · ✖ — убрать идею</i>"
    rows = [[InlineKeyboardButton(text=f"▶ {i}", callback_data=f"agent:idea:{m['id']}") for i, m in enumerate(items, 1)],
            [InlineKeyboardButton(text=f"✖ {i}", callback_data=f"agent:noidea:{m['id']}") for i, m in enumerate(items, 1)], back]
    return text, InlineKeyboardMarkup(inline_keyboard=rows)


HELP = ("🤖 <b>Как пользоваться агентом</b>\n"
        "Я — ИИ-разработчик PRISMA. Работаю сам, без перерывов: беру задачу, пишу код и проверяю его автотестами. "
        "Когда все проверки зелёные и ревьюер не против — сам принимаю и сливаю задачу (не чаще раза в 15 минут, чтобы бот не перезапускался каждую минуту). "
        "Если задача сломалась или конфликтует с новым кодом — обновляю её или переделываю заново.\n\n"
        "🔒 <b>Без вас не сливаю только две вещи</b>: правки моего собственного кода и изменения базы данных. Их карточка приходит с пометкой «Нужно ваше решение».\n\n"
        "📋 <b>Очередь</b> — что готово и ждёт слияния. Нажмите №, чтобы прочитать; ✅ Принять или ❌ Отклонить можно и самому.\n"
        "↩ <b>Откатить</b> — кнопка под сообщением «слито»: я отдельной задачей верну прежний код.\n"
        "💡 <b>Идеи</b> — что я придумал по ходу работы. «▶» — сделаю это следующим, «✖» — уберу.\n"
        "⏸ <b>Пауза</b> — остановить работу, «▶ Продолжить» вернёт её.\n\n"
        "✍️ <b>Дать задачу</b>: <code>/task что сделать</code> — я начну в течение минуты. Или просто ответьте на моё сообщение / "
        "упомяните меня: можно спросить «что сейчас делаешь?».\n"
        "Сообщения админов для меня приоритет, сообщения остальных — предложения.\n\n"
        "Команды: /agent — панель, /task, /ideas, /agent_auto on|off — автослияние, /agent_pause, /agent_resume, /agent_report")


async def detail(pr_number: int, header: str = "") -> tuple[str, InlineKeyboardMarkup]:
    waiting = await waiting_goals()
    pos = next((i for i, g in enumerate(waiting, 1) if g["pr_number"] == pr_number), None)
    g = next((g for g in waiting if g["pr_number"] == pr_number), None)
    back = [InlineKeyboardButton(text="← К списку", callback_data="agent:list")]
    if not g:
        return "Эта задача уже обработана.", InlineKeyboardMarkup(inline_keyboard=[back])
    review = g.get("review") or {}
    lines = ([header] if header else []) + [f"<b>№{pos} · {short(g.get('title'), 80)}</b>", f"💡 {short(review.get('plain') or g.get('expected'), 240)}", _status_line(g)]
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
