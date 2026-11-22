"""Merge gate behind the single «Слить» button. All checks are in code; the model has no say here."""
from __future__ import annotations

from db import rpc

from . import config, github


async def evaluate(number: int, *, owner: bool, override: bool = False) -> tuple[bool, str, dict]:
    """Return (allowed, human_text, pr_info). Pure decision: it merges nothing."""
    info = await github.pr_info(number)
    if info.get("error"):
        return False, "Не смог прочитать PR: " + str(info["error"])[:120], info
    if info.get("merged"):
        return False, "Этот PR уже слит.", info
    if info.get("state") != "open":
        return False, "PR закрыт.", info
    if not github.valid_branch(str(info.get("head_ref") or "")):
        return False, "Это не ветка агента (agent/*) — через эту кнопку не сливаю.", info
    kinds = github.classify_paths(info.get("paths") or [])
    if kinds["refused"]:
        return False, "PR меняет supabase/migrations: такую миграцию нужно применить к базе вручную, кнопка не сливает.", info
    ci = await github.ci(str(info.get("head_sha") or ""))
    if ci.get("error") or ci.get("pending") or ci.get("failed"):
        return False, f"CI не зелёный ({ci.get('passed', 0)}/{ci.get('total', 0)}, упало: {', '.join(ci.get('failing') or []) or '—'}, в процессе: {ci.get('pending', 0)}).", info
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    verdict = ((goal or {}).get("review") or {}).get("verdict")
    if verdict == "BLOCK" and not (owner and override):
        return False, "Ревьюер поставил BLOCK. Владелец может слить принудительно.", info
    return True, "ok", info


def can_merge(user_id: int, permissions: list[str]) -> bool:
    return "*" in (permissions or []) or user_id in config.MERGE_ADMIN_IDS


async def do_merge(number: int, *, owner: bool, override: bool = False) -> tuple[bool, str]:
    ok, text, info = await evaluate(number, owner=owner, override=override)
    if not ok:
        return False, text
    merged, detail = await github.merge(number, str(info.get("title") or f"PR #{number}"))
    if not merged:
        return False, "GitHub не слил: " + detail[:150]
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    note = "после слияния: затронуты файлы агента" if github.classify_paths(info.get("paths") or [])["self"] else ""
    if goal:
        await rpc.bot_agent_goal_save(goal["id"], {"merged": True, "status": "done"})
        await rpc.bot_agent_mem_add("decision", f"PR #{number} «{goal.get('title')}» слит админом. {note}".strip(), [], 3, False)
    await rpc.bot_agent_journal_add("merge", f"PR #{number} слит админом", {"pr": number})
    return True, "Слито в основную ветку. Деплой пойдёт автоматически."
