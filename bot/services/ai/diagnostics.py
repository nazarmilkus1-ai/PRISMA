"""Diagnostics for the admin Copilot: recent bot errors and bug reports.

The bot cannot edit its own code. A bug found by the Copilot becomes a GitHub Issue
(when GITHUB_TOKEN + GITHUB_REPO are set); the fix is then a normal reviewed PR.
Logged text is redacted before it is ever shown to a model or filed.
"""
from __future__ import annotations

import logging
import os
import re
from collections import deque

import aiohttp

_SECRET = re.compile(
    r"(sk-[A-Za-z0-9_\-]{8,}|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]*|"
    r"gh[pousr]_[A-Za-z0-9]{20,}|\b\d{8,10}:[A-Za-z0-9_\-]{30,}|"
    r"(?i:(?:key|token|secret|password|apikey|authorization)[\"'=: ]+)[^\s\"',;]{6,})"
)
_buffer: deque[str] = deque(maxlen=60)


def redact(text: str) -> str:
    return _SECRET.sub("[скрыто]", text or "")


class _RingHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        try:
            line = f"{record.levelname} {record.name}: {record.getMessage()}"
            if record.exc_info and record.exc_info[1] is not None:
                line += f" | {type(record.exc_info[1]).__name__}: {record.exc_info[1]}"
            _buffer.append(redact(line)[:400])
        except Exception:  # logging must never break the bot
            pass


_installed = False


def install() -> None:
    global _installed
    if _installed:
        return
    handler = _RingHandler(level=logging.WARNING)
    logging.getLogger().addHandler(handler)
    _installed = True


def recent_errors(limit: int = 20) -> list[str]:
    return list(_buffer)[-max(1, min(60, limit)):]


def issue_configured() -> bool:
    return bool(os.getenv("GITHUB_TOKEN", "").strip() and os.getenv("GITHUB_REPO", "").strip())


async def create_issue(title: str, body: str) -> tuple[str | None, str | None]:
    """Return (issue_url, error)."""
    token = os.getenv("GITHUB_TOKEN", "").strip()
    repo = os.getenv("GITHUB_REPO", "").strip()
    if not token or not repo or not re.fullmatch(r"[\w.\-]+/[\w.\-]+", repo):
        return None, "not configured"
    payload = {"title": redact(title)[:120], "body": redact(body)[:6000], "labels": ["bug", "from-copilot"]}
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
    try:
        timeout = aiohttp.ClientTimeout(total=20)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(f"https://api.github.com/repos/{repo}/issues", json=payload, headers=headers) as resp:
                data = await resp.json(content_type=None)
                if resp.status >= 300:
                    return None, f"GitHub HTTP {resp.status}"
                return str(data.get("html_url")), None
    except Exception as exc:
        return None, type(exc).__name__
