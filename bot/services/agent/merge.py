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
    if info.get("mergeable") is False:
        return False, "Конфликт с основной веткой: агент сам обновит ветку или пересоберёт задачу заново, ничего нажимать не нужно.", info
    if not github.valid_branch(str(info.get("head_ref") or "")):
        return False, "Это не ветка агента (agent/*) — через эту кнопку не сливаю.", info
    kinds = github.classify_paths(info.get("paths") or [])
    if kinds["refused"]:
        return False, "PR меняет supabase/migrations: такую миграцию нужно применить к базе вручную, кнопка не сливает.", info
    ci = await github.ci(str(info.get("head_sha") or ""))
    if not ci.get("error") and not ci.get("total"):
        return False, "Автопроверки ещё не запустились — подождите минуту и нажмите снова.", info
    if ci.get("error") or ci.get("pending") or ci.get("failed"):
        return False, f"CI не зелёный ({ci.get('passed', 0)}/{ci.get('total', 0)}, упало: {', '.join(ci.get('failing') or []) or '—'}, в процессе: {ci.get('pending', 0)}).", info
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    verdict = ((goal or {}).get("review") or {}).get("verdict")
    if verdict == "BLOCK" and not (owner and override):
        return False, "Ревьюер поставил BLOCK. Владелец может слить принудительно.", info
    return True, "ok", info


_MERGE_PERMS = {"*", "ops.manage", "admin.manage"}


def can_merge(user_id: int, permissions: list[str]) -> bool:
    """Owner or any top admin (ops/admin management), plus ids listed in AGENT_MERGE_ADMIN_IDS."""
    return bool(_MERGE_PERMS & set(permissions or [])) or user_id in config.MERGE_ADMIN_IDS


async def do_merge(number: int, *, owner: bool, override: bool = False, who: str = "админом") -> tuple[bool, str]:
    ok, text, info = await evaluate(number, owner=owner, override=override)
    if not ok:
        return False, text
    out = await github.merge_pr(number, str(info.get("title") or f"PR #{number}"))
    if not out["ok"]:
        return False, "GitHub не слил: " + out["message"][:150]
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    note = "после слияния: затронуты файлы агента" if github.classify_paths(info.get("paths") or [])["self"] else ""
    if goal:
        review = {**(goal.get("review") or {}), "merge_sha": out.get("sha")}  # kept for the «Откатить» button
        await rpc.bot_agent_goal_save(goal["id"], {"merged": True, "status": "done", "review": review})
        await rpc.bot_agent_mem_add("decision", f"PR #{number} «{goal.get('title')}» слит {who}. {note}".strip(), [], 3, False)
    await rpc.bot_agent_journal_add("merge", f"PR #{number} слит {who}", {"pr": number})
    return True, "Слито в основную ветку. Деплой пойдёт автоматически."


async def revert_task(number: int) -> tuple[str, str] | None:
    """(title, task text) for the agent to undo a merged PR: the files come back from the commit before the merge. None if unknown."""
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    sha = ((goal or {}).get("review") or {}).get("merge_sha")
    if not goal or not sha:
        return None
    parent = await github.commit_parent(str(sha))
    info = await github.pr_info(number)
    paths = [p for p in (info.get("paths") or []) if not p.startswith(config.MERGE_REFUSED_PREFIXES)][:8]
    if not parent or not paths:
        return None
    title = f"Откатить: {goal.get('title')}"[:200]
    text = (f"Откати изменения слитого PR #{number} «{goal.get('title')}». Состояние ДО слияния — коммит {parent}: прочитай нужные файлы через "
            f"repo_read с ref={parent} и верни их одним коммитом (edit/commit). Файлы: {', '.join(paths)}. Если файл появился только в этом PR — удали его "
            "(delete: true). Ничего другого не меняй.")
    return title, text


async def reject(number: int) -> tuple[bool, str]:
    """Decline a finished change: the PR is closed and the agent remembers that people did not want it."""
    info = await github.pr_info(number)
    if info.get("error"):
        return False, "Не смог прочитать задачу: " + str(info["error"])[:100]
    if info.get("merged"):
        return False, "Эта задача уже принята."
    if not github.valid_branch(str(info.get("head_ref") or "")):
        return False, "Это не задача агента."
    err = await github.close_pr(number)
    if err:
        return False, "GitHub не закрыл: " + err[:100]
    goals = (await rpc.bot_agent_goals_list(None, 50)).data or []
    goal = next((g for g in goals if g.get("pr_number") == number), None)
    if goal:
        await rpc.bot_agent_goal_save(goal["id"], {"status": "dropped"})
        await rpc.bot_agent_mem_add("decision", f"Админ ОТКЛОНИЛ задачу «{goal.get('title')}». Не повторяй такое без новой причины.", [], 4, False)
    await rpc.bot_agent_journal_add("event", f"Задача #{number} отклонена админом", {"pr": number})
    return True, "Отклонено."
