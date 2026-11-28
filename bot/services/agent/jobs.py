"""Tasks that people hand to the agent: the admin queue, ideas «в работу», and the wake-up that starts a cycle right away."""
from __future__ import annotations

import re

from db import rpc

from . import config

_WORDS = re.compile(r"[\w]{4,}", re.U)

MAX_QUEUED = 10
_QUEUE_STATUS = "paused"  # queued tasks wait here until the agent picks them up
QUEUE_SOURCES = ("admin", "redo")  # people's tasks first-class; «redo» = the agent rebuilding a PR that could not be saved


def make_title(text: str) -> str:
    one = " ".join((text or "").split())
    if len(one) <= 80:
        return one if len(one) >= 3 else "Задача от админа"
    return one[:80].rsplit(" ", 1)[0].rstrip(",;:- ") + "…"


def _words(text: str) -> set[str]:
    return set(_WORDS.findall((text or "").lower()))


async def wake() -> None:
    """Make the worker claim a cycle on its next tick (≤60 s) instead of waiting for the 10-minute timer."""
    await rpc.bot_agent_state_patch({"last_cycle": None})


async def queued() -> list[dict]:
    goals = (await rpc.bot_agent_goals_list(_QUEUE_STATUS, 30)).data or []
    return sorted((g for g in goals if g.get("source") in QUEUE_SOURCES), key=lambda g: (g.get("source") != "admin", g["id"]))


async def add_task(text: str, who: str, source: str = "admin", title: str | None = None) -> tuple[dict | None, str]:
    """Queue a task. Returns (goal, note); goal is None when nothing was queued (note says why)."""
    if not config.CODE_ACCESS:
        return None, ("Я больше не меняю код: работаю помощником админов. Могу найти причину проблемы, посмотреть логи и код "
                      "и подробно описать, что нужно поправить, — задачу на изменение передайте разработчику.")
    text = " ".join((text or "").split())[:1400]
    if len(text) < 6:
        return None, "Опишите задачу подробнее (хотя бы несколько слов)."
    waiting = await queued()
    if len(waiting) >= MAX_QUEUED:
        return None, f"В очереди уже {len(waiting)} задач от админов — дождитесь, пока я их сделаю."
    wanted = _words(text)
    for g in waiting:
        theirs = _words(f"{g.get('title')} {g.get('expected')}")
        if wanted and theirs and len(wanted & theirs) / min(len(wanted), len(theirs)) >= 0.7:
            return g, "Похожая задача уже в очереди."
    why = f"Просьба админа {who}" if source == "admin" else f"Автоматическая переделка ({who})"
    res = await rpc.bot_agent_goal_save(None, {"title": (title or make_title(text))[:200], "why": why[:300], "expected": text,
                                               "source": source, "status": _QUEUE_STATUS})
    if res.error or not isinstance(res.data, dict):
        return None, "Не получилось записать задачу, попробуйте ещё раз."
    await rpc.bot_agent_journal_add("event", (f"Админ {who} поставил задачу: " if source == "admin" else "Задача на переделку: ") + (title or make_title(text)),
                                    {"goal": res.data.get("id")})
    return res.data, ""


async def ideas(limit: int = 6) -> list[dict]:
    res = await rpc.bot_agent_mem_list("idea", limit)
    return [m for m in (res.data or []) if isinstance(m, dict) and m.get("id")] if not res.error and isinstance(res.data, list) else []


async def take_idea(mem_id: int, who: str) -> tuple[dict | None, str]:
    found = next((m for m in await ideas(20) if int(m.get("id")) == int(mem_id)), None)
    if not found:
        return None, "Эта идея уже взята или удалена."
    goal, note = await add_task(str(found.get("body") or ""), who)
    if goal:
        await rpc.bot_agent_mem_forget(int(mem_id))
    return goal, note


async def drop_idea(mem_id: int) -> bool:
    res = await rpc.bot_agent_mem_forget(int(mem_id))
    if not res.error:
        await rpc.bot_agent_mem_add("decision", "Админ убрал одну из моих идей как ненужную — не предлагай такое же снова.", [], 3, False)
    return not res.error


def cycle_minutes() -> int:
    return max(1, config.CYCLE_SECONDS // 60)
