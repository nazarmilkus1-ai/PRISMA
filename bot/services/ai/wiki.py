"""Public Wiki pages as extra context for the navigator (cached, never required)."""
from __future__ import annotations

import re
import time

from db.rpc import bot_get_public_wiki

TTL_OK = 600.0
TTL_EMPTY = 60.0
MAX_CHARS = 5000
PER_PAGE = 700

_cache: dict = {"at": 0.0, "ttl": 0.0, "text": ""}
_NOISE = re.compile(r"<[^>]+>|[#*_`>]+")


def _clean(text: str) -> str:
    return re.sub(r"\s+", " ", _NOISE.sub(" ", text or "")).strip()


def format_pages(pages: list, max_chars: int = MAX_CHARS) -> str:
    chunks: list[str] = []
    used = 0
    for page in pages:
        if not isinstance(page, dict):
            continue
        title = _clean(str(page.get("title") or ""))
        body = _clean(str(page.get("content") or page.get("excerpt") or ""))[:PER_PAGE]
        if not title and not body:
            continue
        chunk = f"[{title or 'Без названия'}] {body}"
        if used + len(chunk) > max_chars:
            break
        chunks.append(chunk)
        used += len(chunk) + 1
    return "\n".join(chunks)


async def wiki_context() -> str:
    now = time.time()
    if now - _cache["at"] < _cache["ttl"]:
        return _cache["text"]
    text = ""
    try:
        result = await bot_get_public_wiki("", 30)
        if not result.error and isinstance(result.data, list):
            text = format_pages(result.data)
    except Exception:  # the Wiki is optional context: never break an answer because of it
        text = ""
    _cache.update(at=now, ttl=TTL_OK if text else TTL_EMPTY, text=text)
    return text
