"""Cheap checks that stop the agent from pushing code that is obviously broken, and readers of failed CI logs.

Pure functions only (no network): everything here is unit-tested.
"""
from __future__ import annotations

import ast
import json
import re

# Same rule as scripts/verify-architecture.mjs: bot DB/service layers talk to Supabase through RPC wrappers only.
_DIRECT_CRUD = re.compile(r"supabase\.table\(|supabase\.from\(|\.insert\(|\.update\(|\.delete\(")
_CRUD_DIRS = ("bot/db/", "bot/services/")


_LOG_NAMES = ("logger", "logging")


def undefined_log_names(tree: ast.AST) -> list[str]:
    """Names from _LOG_NAMES that a module uses but never defines (import, assignment, def, argument, ...).

    The usual slip when the model adds `logger.error(...)` to a file that has no logger: it passes the syntax check and
    the tests, then raises NameError in production inside the very `except` block it was meant to improve."""
    bound: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                if alias.name == "*":
                    return []
                bound.add((alias.asname or alias.name).split(".")[0])
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            bound.add(node.name)
        elif isinstance(node, ast.arg):
            bound.add(node.arg)
        elif isinstance(node, ast.ExceptHandler) and node.name:
            bound.add(node.name)
        elif isinstance(node, (ast.Global, ast.Nonlocal)):
            bound |= set(node.names)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            bound.add(node.id)
    used = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    return [name for name in _LOG_NAMES if name in used and name not in bound]


def banned_theme(text: str, themes) -> str | None:
    """The first theme from `themes` that `text` falls under, or None.

    A theme is a phrase the people closed after a flood of near-identical PRs (kept in agent_state.banned_themes).
    Parts joined by «+» must all occur in the text (case-insensitive substring), so «except+лог» matches
    «Добавить лог в except» but not a task about tests."""
    low = (text or "").lower()
    for theme in themes if isinstance(themes, (list, tuple)) else []:
        parts = [p.strip() for p in str(theme).lower().split("+") if p.strip()]
        if parts and all(p in low for p in parts):
            return str(theme)
    return None


def precheck(files: list[dict]) -> str | None:
    """Return a short error for the model (Russian, one problem per line) or None when the files look sane."""
    problems: list[str] = []
    for f in files:
        if f.get("delete"):
            continue
        path, text = str(f.get("path") or ""), str(f.get("content") or "")
        if path.endswith(".py"):
            try:
                tree = ast.parse(text, filename=path)
            except SyntaxError as exc:
                problems.append(f"{path}: синтаксическая ошибка Python, строка {exc.lineno}: {exc.msg}")
                continue
            for name in undefined_log_names(tree):
                problems.append(f"{path}: используется `{name}`, но в файле он не объявлен (будет NameError). "
                                "Добавь `import logging` и `logger = logging.getLogger(__name__)` или не логируй.")
            if path.startswith(_CRUD_DIRS) and "/tests/" not in path and _DIRECT_CRUD.search(text):
                problems.append(f"{path}: запрещено прямое обращение к базе и методы insert/update/delete в bot/db и bot/services "
                                "(автопроверка архитектуры упадёт). Для словаря используй `d |= {...}`, для базы — готовые функции из db/rpc.py.")
        elif path.endswith(".json"):
            try:
                json.loads(text)
            except ValueError as exc:
                problems.append(f"{path}: некорректный JSON: {str(exc)[:80]}")
        if "\x00" in text:
            problems.append(f"{path}: в файле нулевой байт")
        if re.search(r"^(<<<<<<<|>>>>>>>) ", text, re.M):
            problems.append(f"{path}: остались маркеры конфликта слияния")
    return "\n".join(problems[:5]) or None


REDACTED = "[скрыто]"  # what services.ai.diagnostics.redact puts in place of a secret in the text the model reads


def shrink_problem(old: dict[str, str | None], files: list[dict]) -> str | None:
    """Refuse a commit that makes an existing file much shorter or deletes it: a model that saw only the start of a file and sends it back loses the rest.

    `old` maps path -> the text on the base branch (None when the file is new). Short files are exempt."""
    from . import config
    problems: list[str] = []
    for f in files:
        path, before = str(f.get("path") or ""), old.get(str(f.get("path") or ""))
        if before is None:
            continue
        if REDACTED in str(f.get("content") or "") and REDACTED not in before:
            problems.append(f"{path}: в файле появился маркер «{REDACTED}» — это замаскированный секрет из repo_read, а не настоящий текст. "
                            "Не присылай файл целиком: правь точечно через edit, он работает с настоящим текстом.")
            continue
        was = before.count("\n") + 1
        if f.get("delete"):
            if was >= 15:
                problems.append(f"{path}: нельзя удалять существующий файл ({was} строк). Если он правда не нужен, оставь его и напиши идею в память.")
            continue
        now = str(f.get("content") or "").count("\n") + 1
        if was >= config.SHRINK_MIN_LINES and now < was * 0.7:
            problems.append(f"{path}: после твоей правки файл стал короче с {was} до {now} строк — похоже, потерян кусок кода (ты видел только начало файла?). "
                            "Не присылай файл целиком: правь точечно через edit (old_str → new_str).")
    return "\n".join(problems[:5]) or None


_TS = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ")
_UNITTEST_FAIL = re.compile(r"^(ERROR|FAIL): ")
_OTHER_FAIL = re.compile(r"##\[error\]|error TS\d+|Error: |AssertionError|Traceback \(most recent|FAILED|forbidden|failures?:", re.I)


def failure_excerpt(log: str, max_chars: int = 2600) -> str:
    """The few lines of a CI job log that explain why it failed (unittest, tsc/next, architecture gate)."""
    lines = [_TS.sub("", ln).rstrip() for ln in (log or "").splitlines()]
    if not lines:
        return ""
    hits = [i for i, ln in enumerate(lines) if _UNITTEST_FAIL.match(ln)]
    if hits:
        start = hits[0]
        end = next((i for i in range(start, len(lines)) if lines[i].startswith("FAILED (")), min(len(lines), start + 60))
        picked = lines[start:min(end + 1, start + 70)]
    else:
        idx = [i for i, ln in enumerate(lines) if _OTHER_FAIL.search(ln) and "Process completed with exit code" not in ln]
        if not idx:
            picked = lines[-25:]
        else:
            keep: list[int] = []
            for i in idx[:10]:
                keep.extend(range(max(0, i - 2), min(len(lines), i + 3)))
            picked = [lines[i] for i in sorted(set(keep))][:60]
    text = "\n".join(ln[:240] for ln in picked if ln.strip())
    return text[:max_chars]


def norm_tasks(raw) -> list[dict]:
    """The plan as [{"t": text, "done": bool}], whatever shape the model (or an older record) used."""
    out = []
    for item in raw if isinstance(raw, list) else []:
        if isinstance(item, str):
            text, done = item, False
        elif isinstance(item, dict):
            text, done = str(item.get("t") or item.get("title") or item.get("text") or item.get("task") or ""), bool(item.get("done"))
        else:
            continue
        if text.strip():
            out.append({"t": text.strip()[:200], "done": done})
    return out[:12]


def plan_progress(tasks, has_pr: bool = False) -> int | None:
    """Progress from the plan itself: share of finished steps (max 90) + 5 for a plan + 5 once a PR exists. None without a plan."""
    items = norm_tasks(tasks)
    if not items:
        return None
    done = sum(1 for t in items if t["done"])
    return max(5, min(95, round(90 * done / len(items)) + (5 if has_pr else 0)))
