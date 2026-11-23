"""Tool belt of the autonomous agent. Every tool returns a JSON-able dict; hard limits live here, not in the prompt."""
from __future__ import annotations

import ipaddress
import json
import logging
import re
import socket
import time
from dataclasses import dataclass, field
from urllib.parse import urlparse

import aiohttp

from db import rpc
from services.ai import ops
from services.ai.diagnostics import redact

from . import config, github

logger = logging.getLogger(__name__)


@dataclass
class Ctx:
    bot: object
    goal: dict | None = None
    says: int = 0
    commits: int = 0
    finished: bool = False
    summary: str = ""
    new_head: bool = False
    notes: list[str] = field(default_factory=list)
    next_step: str = ""
    actions: list[str] = field(default_factory=list)
    step: int = 0
    live_at: float = 0.0
    counts: dict = field(default_factory=dict)
    seen: set = field(default_factory=set)


def _s(name: str, desc: str, props: dict, required: list[str] | None = None) -> dict:
    return {"type": "function", "function": {"name": name, "description": desc,
            "parameters": {"type": "object", "properties": props, "required": required or []}}}


_STR = {"type": "string"}
READ_ONLY = {"repo_read", "repo_search", "web_fetch", "render_status", "render_logs", "vercel_status"}
SCHEMAS = [
    _s("repo_read", "Прочитать файл или список папки в репозитории (по умолчанию из ветки PRISMA; ref — ветка цели).",
       {"path": _STR, "ref": _STR}, ["path"]),
    _s("repo_search", "Поиск текста по коду репозитория.", {"query": _STR}, ["query"]),
    _s("commit", "Один атомарный коммит в ветку текущей цели (создаётся сама, PR открывается сам). files: [{path, content}] "
                 "или {path, delete:true}. Полное содержимое файла, не патч. Нельзя трогать .github/ и env-файлы.",
       {"message": _STR, "files": {"type": "array", "items": {"type": "object"}}}, ["message", "files"]),
    _s("edit", "Точечная правка существующего файла: заменить old_str (точно как в файле, встречается ровно 1 раз) на new_str, "
               "и закоммитить. Предпочитай это вместо commit для изменения существующих файлов.",
       {"path": _STR, "old_str": _STR, "new_str": _STR, "message": _STR}, ["path", "old_str", "new_str", "message"]),
    _s("ci_status", "Состояние CI последнего коммита цели: проценты, упавшие проверки.", {}),
    _s("render_status", "Последние деплои бота на Render.", {}),
    _s("render_logs", "Последние логи бота на Render (без секретов).", {"limit": {"type": "integer"}}),
    _s("vercel_status", "Последние деплои сайта/панели на Vercel.", {}),
    _s("web_fetch", "Прочитать страницу документации (только https и разрешённые доки-сайты).", {"url": _STR}, ["url"]),
    _s("goal_new", "Поставить себе новую цель (своя идея или из просьбы людей). Одновременно одна активная цель.",
       {"title": _STR, "why": _STR, "expected": _STR, "tasks": {"type": "array", "items": {"type": "string"}}}, ["title", "expected"]),
    _s("goal_update", "Обновить цель: прогресс 0-100, задачи, ожидаемый результат, статус (active/done/dropped/paused). "
                      "Менять ожидания и идеи можно. done = работа закончена, PR ждёт кнопку «Слить».",
       {"progress_pct": {"type": "integer"}, "expected": _STR, "status": _STR, "tasks": {"type": "array", "items": {"type": "object"}}}),
    _s("memory_save", "Записать в долгую память факт, урок, решение, идею или предпочтение людей.",
       {"kind": {"type": "string", "enum": ["fact", "lesson", "user", "decision", "idea"]}, "body": _STR,
        "importance": {"type": "integer"}, "pinned": {"type": "boolean"}, "tags": {"type": "array", "items": _STR}}, ["kind", "body"]),
    _s("memory_search", "Поиск по долгой памяти.", {"query": _STR}, ["query"]),
    _s("memory_forget", "Удалить устаревшую заметку по id.", {"id": {"type": "integer"}}, ["id"]),
    _s("say", "Написать в топик админам (редко, коротко: вопрос, важная находка). Лимит 3 за цикл.", {"text": _STR}, ["text"]),
    _s("finish_cycle", "Закончить цикл. summary — что сделано за цикл, ПО-РУССКИ, простыми словами без жаргона (1-3 предложения); "
                       "next — что будешь делать дальше (1 предложение). Попадает в отчёт для админов.",
       {"summary": _STR, "next": _STR}, ["summary"]),
]


_WORDS = re.compile(r"[\w]{4,}", re.U)


def _similar(a: str, b: str) -> bool:
    wa, wb = set(_WORDS.findall(a.lower())), set(_WORDS.findall(b.lower()))
    return bool(wa and wb) and len(wa & wb) / min(len(wa), len(wb)) >= 0.6


def wrapup_schemas() -> list[dict]:
    """Last steps of a cycle: only bookkeeping tools, so the model finishes with a proper summary."""
    return [t for t in SCHEMAS if t["function"]["name"] in {"goal_update", "memory_save", "finish_cycle"}]


def act_schemas() -> list[dict]:
    """After a few steps of pure reading the model only gets tools that change things, so it cannot loop on reads."""
    return [t for t in SCHEMAS if t["function"]["name"] not in READ_ONLY | {"ci_status"}]


def _clip(obj, n: int = config.TOOL_RESULT_CHARS) -> str:
    text = json.dumps(obj, ensure_ascii=False, default=str)
    return text if len(text) <= n else text[:n] + '..."(обрезано)"'


async def _day_counter(key: str) -> int:
    state = (await rpc.bot_agent_state_get()).data or {}
    entry = state.get(key) or {}
    return int(entry.get("n", 0)) if entry.get("day") == time.strftime("%Y-%m-%d") else 0


async def bump(key: str, by: int = 1) -> int:
    n = await _day_counter(key) + by
    await rpc.bot_agent_state_patch({key: {"day": time.strftime("%Y-%m-%d"), "n": n}})
    return n


def _host_ok(url: str) -> str | None:
    parts = urlparse(url)
    host = (parts.hostname or "").lower()
    if parts.scheme != "https" or not host or parts.port not in (None, 443) or parts.username:
        return None
    if not any(host == d or host.endswith("." + d) for d in config.WEB_ALLOWLIST):
        return None
    try:
        for info in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM):
            ip = ipaddress.ip_address(info[4][0])
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
                return None
    except OSError:
        return None
    return host


async def web_fetch(url: str) -> dict:
    if not _host_ok(url):
        return {"error": "домен не из белого списка: " + ", ".join(config.WEB_ALLOWLIST[:6]) + "…"}
    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=15)) as s:
            async with s.get(url, allow_redirects=False, headers={"User-Agent": "prisma-agent"}) as r:
                if r.status >= 300:
                    return {"error": f"HTTP {r.status}"}
                raw = (await r.content.read(300_000)).decode("utf-8", "ignore")
    except Exception as exc:
        return {"error": type(exc).__name__}
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", raw)
    text = re.sub(r"<[^>]+>", " ", text)
    return {"url": url, "text": redact(re.sub(r"\s+", " ", text))[:6000]}


async def _goal_branch(ctx: Ctx) -> tuple[str | None, str | None]:
    goal = ctx.goal
    if not goal:
        return None, "нет активной цели: сначала goal_new"
    branch = goal.get("branch")
    if not branch:
        branch = github.new_branch_name(goal.get("title") or "work")
        res = await rpc.bot_agent_goal_save(goal["id"], {"branch": branch})
        if res.error:
            return None, "не удалось сохранить ветку"
        goal["branch"] = branch
    return branch, None


async def _commit(ctx: Ctx, message: str, files) -> dict:
    if await _day_counter("commits_day") >= config.MAX_COMMITS_PER_DAY:
        return {"error": "дневной лимит коммитов исчерпан"}
    clean, err = github.validate_files(files)
    if err:
        return {"error": err}
    branch, err = await _goal_branch(ctx)
    if err:
        return {"error": err}
    _, err = await github.ensure_branch(branch)
    if err:
        return {"error": err}
    sha, err = await github.commit_files(branch, clean, message or "agent: update")
    if err:
        return {"error": err}
    await bump("commits_day")
    ctx.commits += 1
    ctx.new_head = True
    goal = ctx.goal
    patch = {"head_sha": sha}
    if not goal.get("pr_number"):
        body = (f"## {goal.get('title')}\n\n**Зачем:** {goal.get('why') or '—'}\n\n**Ожидаемый результат:** {goal.get('expected') or '—'}\n\n"
                "Автор: автономный агент PRISMA. Сливается только кнопкой админа в топике.")
        pr, perr = await github.open_pr(branch, f"agent: {goal.get('title')}", body)
        if pr and pr.get("number"):
            patch["pr_number"] = pr["number"]
            goal["pr_number"] = pr["number"]
        elif perr:
            ctx.notes.append(f"PR не открылся: {perr}")
    await rpc.bot_agent_goal_save(goal["id"], patch)
    goal |= patch
    return {"ok": True, "branch": branch, "commit": sha[:10], "pr": goal.get("pr_number")}


def label(name: str, a: dict) -> str:
    path = str(a.get("path") or "")[:70]
    return {
        "repo_read": f"📖 Читаю {path}", "repo_search": f"🔎 Ищу в коде «{str(a.get('query') or '')[:40]}»",
        "edit": f"✂️ Правлю {path}", "commit": f"✍️ Коммит: {str(a.get('message') or '')[:60]}", "ci_status": "🚦 Проверяю тесты (CI)",
        "render_status": "🛰 Смотрю деплои бота (Render)", "render_logs": "🛰 Читаю логи бота", "vercel_status": "▲ Смотрю деплои сайта (Vercel)",
        "web_fetch": "🌐 Читаю документацию", "goal_new": f"🎯 Новая цель: {str(a.get('title') or '')[:60]}",
        "goal_update": "📈 Обновляю прогресс", "memory_save": "🧠 Запоминаю", "memory_search": "🧠 Вспоминаю",
        "memory_forget": "🧠 Чищу память", "say": "💬 Пишу в топик", "finish_cycle": "🏁 Подвожу итог",
    }.get(name, name)


async def run_tool(ctx: Ctx, name: str, args: dict) -> str:
    ctx.counts[name] = ctx.counts.get(name, 0) + 1
    ctx.actions.append(label(name, args if isinstance(args, dict) else {}))
    from .report import live_progress  # late import: report imports github, tools must stay importable without it
    await live_progress(ctx)
    args = args if isinstance(args, dict) else {}
    caps = {"repo_read": 10, "repo_search": 4, "ci_status": 2}
    if name in caps and ctx.counts.get(name, 0) > caps[name]:
        return _clip({"error": f"лимит {caps[name]} вызовов «{name}» за цикл исчерпан. Действуй: edit/commit, goal_update или finish_cycle."})
    if name in READ_ONLY:
        key = (name, json.dumps(args, sort_keys=True, ensure_ascii=False))
        if key in ctx.seen:
            return _clip({"error": "ты уже делал точно такой вызов, результат не изменится. Переходи к действию: edit/commit, goal_update или finish_cycle."})
        ctx.seen.add(key)
    try:
        return _clip(await _dispatch(ctx, name, args), 26_000 if name == "repo_read" else config.TOOL_RESULT_CHARS)
    except Exception as exc:  # a tool must never crash the cycle
        logger.warning("agent tool %s failed: %s", name, exc)
        return _clip({"error": f"{type(exc).__name__}"})


async def _dispatch(ctx: Ctx, name: str, a: dict):
    goal = ctx.goal
    if name == "repo_read":
        ref = a.get("ref") if github.valid_branch(str(a.get("ref") or "")) else None
        return await github.read(str(a.get("path") or ""), ref or (goal or {}).get("branch") or None)
    if name == "repo_search":
        found = await github.search(str(a.get("query") or ""))
        if not found.get("error") and not found.get("hits"):
            found["hint"] = "поиск пуст (индекс GitHub неполный): открывай файлы напрямую через repo_read по списку файлов"
        return found
    if name == "commit":
        return await _commit(ctx, str(a.get("message") or ""), a.get("files"))
    if name == "edit":
        old, new = str(a.get("old_str") or ""), str(a.get("new_str") or "")
        if not old or old == new:
            return {"error": "old_str пустой или совпадает с new_str"}
        ref = (goal or {}).get("branch") if (goal or {}).get("branch") and (goal or {}).get("head_sha") else None
        text, err = await github.read_raw(str(a.get("path") or ""), ref)
        if err or text is None:
            return {"error": f"не смог прочитать файл: {err}"}
        if text.count(old) != 1:
            return {"error": f"old_str должен встречаться ровно 1 раз, сейчас {text.count(old)}: прочитай файл и скопируй кусок точно"}
        result = await _commit(ctx, str(a.get("message") or "agent: edit"), [{"path": str(a.get("path")), "content": text.replace(old, new, 1)}])
        return result
    if name == "ci_status":
        return await github.ci((goal or {}).get("head_sha") or "")
    if name == "render_status":
        return await ops.render_status()
    if name == "render_logs":
        return await ops.render_logs(int(a.get("limit") or 40))
    if name == "vercel_status":
        return await ops.vercel_status()
    if name == "web_fetch":
        return await web_fetch(str(a.get("url") or ""))
    if name == "goal_new":
        active = (await rpc.bot_agent_goals_list("active", 1)).data or []
        if active:
            return {"error": f"уже есть активная цель #{active[0].get('id')}: закончи её (goal_update status=done) или брось"}
        waiting = [g for g in ((await rpc.bot_agent_goals_list("done", 20)).data or []) if g.get("pr_number") and not g.get("merged_at")]
        if len(waiting) >= 3:
            return {"error": "уже 3 готовых изменения ждут кнопки «Слить». Новую цель не ставь: проверь тесты (ci_status) этих PR, "
                             "поправь замечания или запиши идеи в память и заверши цикл."}
        recent = (await rpc.bot_agent_goals_list(None, 30)).data or []
        if any(_similar(str(a.get("title") or ""), str(g.get("title") or "")) for g in recent if isinstance(g, dict)):
            return {"error": "похожая цель уже есть или была. Придумай другую небольшую цель или продолжи ту, что в работе."}
        res = await rpc.bot_agent_goal_save(None, {
            "title": str(a.get("title") or "")[:200], "why": str(a.get("why") or "")[:1500], "expected": str(a.get("expected") or "")[:1500],
            "tasks": [{"t": str(t)[:200], "done": False} for t in (a.get("tasks") or [])][:12] if isinstance(a.get("tasks"), list) else []})
        if res.error or not isinstance(res.data, dict):
            return {"error": "не удалось создать цель"}
        ctx.goal = res.data
        return {"ok": True, "goal_id": res.data.get("id")}
    if name == "goal_update":
        if not goal:
            return {"error": "нет активной цели"}
        patch = {k: a[k] for k in ("progress_pct", "expected", "tasks") if k in a}
        if a.get("status") in {"active", "done", "dropped", "paused"}:
            patch["status"] = a["status"]
            if a["status"] == "done":
                patch["progress_pct"] = 100
        res = await rpc.bot_agent_goal_save(goal["id"], patch)
        if res.error:
            return {"error": "не удалось обновить"}
        goal |= res.data if isinstance(res.data, dict) else {}
        return {"ok": True, "progress_pct": goal.get("progress_pct"), "status": goal.get("status")}
    if name == "memory_save":
        body = redact(str(a.get("body") or ""))[:1500]
        if len(body) < 8:
            return {"error": "слишком коротко"}
        res = await rpc.bot_agent_mem_add(str(a.get("kind") or "fact"), body,
                                          [str(t)[:30] for t in (a.get("tags") or [])][:6] if isinstance(a.get("tags"), list) else [],
                                          max(1, min(5, int(a.get("importance") or 3))), bool(a.get("pinned")))
        return {"error": "не записалось"} if res.error else {"ok": True, "id": res.data}
    if name == "memory_search":
        res = await rpc.bot_agent_mem_search(str(a.get("query") or ""), 8)
        return {"notes": [{"id": m.get("id"), "kind": m.get("kind"), "body": str(m.get("body"))[:500]} for m in (res.data or [])]} if not res.error else {"error": "поиск не сработал"}
    if name == "memory_forget":
        res = await rpc.bot_agent_mem_forget(int(a.get("id") or 0))
        return {"ok": not res.error}
    if name == "say":
        if ctx.says >= config.MAX_SAYS_PER_CYCLE:
            return {"error": "лимит сообщений за цикл"}
        ctx.says += 1
        from .report import post
        await post(ctx.bot, "💬 " + redact(str(a.get("text") or ""))[:1500])
        return {"ok": True}
    if name == "finish_cycle":
        ctx.finished = True
        ctx.summary = str(a.get("summary") or "")[:900]
        ctx.next_step = str(a.get("next") or "")[:300]
        return {"ok": True}
    return {"error": f"неизвестный инструмент {name}"}
