"""Autonomous mode: the agent merges its own finished PRs, un-sticks conflicting ones and rebuilds what cannot be saved.

What it never does on its own (those PRs wait for a human, with a card): changes to the agent's own code and database migrations.
Everything else needs green automatic checks and a reviewer who does not say BLOCK — the same gate the admin button uses.
"""
from __future__ import annotations

import logging
import re
import time

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from db import rpc

from . import config, github, jobs, merge, report

logger = logging.getLogger(__name__)

MAX_REDOS = 2  # rebuilds from scratch per task before it is given up
_REDO_PREFIX = re.compile(r"^(?:Переделать:\s*)+", re.I)
MERGE_GAP_SECONDS = 900  # one merge per 15 minutes: every merge redeploys the bot, no need to restart it every minute


def enabled(state: dict) -> bool:
    return config.auto_merge_on(state)


def cycle_seconds(state: dict, goals: list[dict]) -> int:
    """How soon the next cycle may start: right after the previous one while there is anything to do."""
    if state.get("paused"):
        return config.CYCLE_SECONDS
    if enabled(state):
        return config.BUSY_CYCLE_SECONDS  # autonomous: always something to build, merge or fix
    for g in goals:
        if g.get("status") == "active" or (g.get("status") == "paused" and g.get("source") in jobs.QUEUE_SOURCES):
            return config.BUSY_CYCLE_SECONDS
    return config.CYCLE_SECONDS


def _today_count(state: dict) -> int:
    entry = state.get("auto_merges") or {}
    return int(entry.get("n", 0)) if entry.get("day") == time.strftime("%Y-%m-%d") else 0


async def redo(goal: dict, why: str, state: dict) -> bool:
    """Close a PR that cannot be merged and queue the same task again on fresh code. After MAX_REDOS it is dropped with a lesson."""
    title = _REDO_PREFIX.sub("", str(goal.get("title") or "")).strip() or "задача"  # a rebuilt task keeps counting under its original name
    key = title[:60].lower()
    redos = dict(state.get("redos") or {})
    used = int(redos.get(key, 0))
    pr = goal.get("pr_number")
    if pr:
        await github.close_pr(int(pr))
    await rpc.bot_agent_goal_save(goal["id"], {"status": "dropped"})
    if used >= MAX_REDOS:
        await rpc.bot_agent_mem_add("lesson", f"Задачу «{title[:120]}» не удалось довести до слияния ({why}) даже после переделок. "
                                              "Не берись за неё снова без совершенно нового подхода.", [], 4, False)
        await rpc.bot_agent_journal_add("event", f"Отказался от задачи «{title[:80]}»: {why}", {"pr": pr})
        return False
    redos[key] = used + 1
    await rpc.bot_agent_state_patch({"redos": redos})
    text = (f"Переделай заново на свежем коде основной ветки: «{title}». Что нужно: {str(goal.get('expected') or title)[:700]}. "
            f"Прошлая попытка (PR #{pr}) не удалась: {why}. Сначала посмотри текущий код (repo_search, repo_read): он мог измениться. "
            "Делай маленькими шагами, чтобы не конфликтовать.")
    new_goal, _ = await jobs.add_task(text, "агент", source="redo", title=f"Переделать: {title}"[:200])
    return bool(new_goal)


async def _unblock(goal: dict, info: dict, state: dict) -> None:
    """The PR conflicts with the base branch: bring the base into it, and if that conflicts for real, rebuild the task."""
    err = await github.update_branch(int(goal["pr_number"]), str(info.get("head_sha") or ""))
    if err is None:
        await rpc.bot_agent_journal_add("event", f"Обновил ветку PR #{goal['pr_number']} свежим кодом", {"pr": goal["pr_number"]})
    elif err == "HTTP 422":
        again = await github.pr_info(int(goal["pr_number"]))  # 422 is also «the branch moved meanwhile»: only a still-conflicting, unchanged PR is rebuilt
        if not again.get("error") and again.get("mergeable") is False and again.get("head_sha") == info.get("head_sha"):
            await redo(goal, "конфликт с основной веткой", state)
    else:
        logger.info("update-branch of PR %s skipped: %s", goal.get("pr_number"), err)


async def _announce(bot, goal: dict, merged_today: int) -> None:
    text = (f"🚀 <b>Принято и слито — сам</b>\n{report._summary(goal)}\n"
            f"<i>Деплой пойдёт автоматически, минуты 2–3. Слито сегодня: {merged_today}.</i>")
    markup = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text="↩ Откатить", callback_data=f"agent:revert:{goal['pr_number']}"),
                                                    InlineKeyboardButton(text="📋 Очередь", callback_data="agent:list")]])
    await report.post(bot, text, markup)


async def step(bot, state: dict) -> None:
    """One pass over finished PRs, oldest first: merge the first ready one, un-stick the conflicting ones. Never raises."""
    if not enabled(state):
        return
    try:
        goals = (await rpc.bot_agent_goals_list("done", 30)).data or []
        waiting = sorted((g for g in goals if g.get("pr_number") and not g.get("merged_at")), key=lambda g: g["pr_number"])
        count = _today_count(state)
        gap_ok = time.time() - float(state.get("last_auto_merge") or 0) >= MERGE_GAP_SECONDS
        merged_now = False
        for g in waiting:
            info = await github.pr_info(int(g["pr_number"]))
            if info.get("error") or info.get("merged") or info.get("state") != "open":
                continue
            kinds = github.classify_paths(info.get("paths") or [])
            manual = "migrations" if kinds["refused"] else ("self" if kinds["self"] else "")
            review = dict(g.get("review") or {})
            if manual != (review.get("manual") or ""):
                review["manual"] = manual
                await rpc.bot_agent_goal_save(g["id"], {"review": review})
            if manual:
                continue
            if info.get("mergeable") is False:
                await _unblock(g, info, state)
                continue
            if merged_now or not gap_ok or count >= config.MAX_AUTO_MERGES_PER_DAY:
                continue
            ok, text = await merge.do_merge(int(g["pr_number"]), owner=False, who="агентом сам")
            if not ok:
                logger.info("auto-merge of PR %s waits: %s", g["pr_number"], text[:120])
                continue
            merged_now = True
            count += 1
            await rpc.bot_agent_state_patch({"last_auto_merge": time.time(), "auto_merges": {"day": time.strftime("%Y-%m-%d"), "n": count}})
            await _announce(bot, g, count)
    except Exception:
        logger.exception("autopilot step failed")
