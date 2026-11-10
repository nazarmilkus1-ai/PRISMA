"""Short conversation memory for PRISMA_AI: last few turns per (chat, user), in RAM only.

It is deliberately small and temporary (30 minutes, 8 messages): enough for follow-ups like
«а как это сделать?», never a profile of the user, and lost on restart.
"""
from __future__ import annotations

import time
from collections import defaultdict, deque

TTL_SECONDS = 1800
MAX_MESSAGES = 8
MAX_CHARS = 600

_store: dict[tuple[int, int], deque] = defaultdict(lambda: deque(maxlen=MAX_MESSAGES))


def _prune(key: tuple[int, int], now: float) -> deque:
    window = _store[key]
    while window and now - window[0][0] > TTL_SECONDS:
        window.popleft()
    return window


def history(chat_id: int, user_id: int, now: float | None = None) -> list[dict]:
    window = _prune((chat_id, user_id), time.time() if now is None else now)
    return [{"role": role, "content": text} for _, role, text in window]


def remember(chat_id: int, user_id: int, role: str, text: str, now: float | None = None) -> None:
    if role not in {"user", "assistant"} or not text:
        return
    now = time.time() if now is None else now
    _prune((chat_id, user_id), now).append((now, role, text[:MAX_CHARS]))


def forget(chat_id: int, user_id: int) -> None:
    _store.pop((chat_id, user_id), None)
