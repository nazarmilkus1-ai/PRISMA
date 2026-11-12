"""Conversation memory for PRISMA_AI / PRISMA_AGENT.

RAM is the fast path; every message is also written to the database (best effort), so after a
restart the last messages of a chat are loaded back (`hydrate`). Answers carry an `answer_id`
and the user's 👍/👎 rating, which the model sees in the history, so it knows how its previous
answers were received. Only the last 16 messages (7 days) are used; rows are trimmed in the DB.
"""
from __future__ import annotations

import logging
import time
import uuid
from collections import defaultdict, deque

logger = logging.getLogger(__name__)

TTL_SECONDS = 7 * 24 * 3600
MAX_MESSAGES = 16
MAX_CHARS = 600

_RATING_NOTE = {1: " [пользователь поставил 👍 этому ответу]", -1: " [пользователь поставил 👎 этому ответу — ответ не помог, постарайся лучше]"}

_store: dict[tuple[int, int], deque] = defaultdict(lambda: deque(maxlen=MAX_MESSAGES))
_hydrated: set[tuple[int, int]] = set()


def _prune(key: tuple[int, int], now: float) -> deque:
    window = _store[key]
    while window and now - window[0]["ts"] > TTL_SECONDS:
        window.popleft()
    return window


def history(chat_id: int, user_id: int, now: float | None = None) -> list[dict]:
    window = _prune((chat_id, user_id), time.time() if now is None else now)
    return [{"role": e["role"], "content": e["text"] + _RATING_NOTE.get(e.get("rating"), "")} for e in window]


_bound: dict[tuple[int, int], tuple[int, str]] = {}


def bind(chat_id: int, message_id: int, owner_id: int, answer_id: str) -> None:
    """Remember which answer a bot message carries, so a Telegram reaction (👍/👎) can be matched to it."""
    _bound[(chat_id, message_id)] = (owner_id, answer_id)
    if len(_bound) > 3000:
        for key in list(_bound)[:1000]:
            _bound.pop(key, None)


def owner_of(chat_id: int, message_id: int) -> tuple[int, str] | None:
    return _bound.get((chat_id, message_id))


def new_answer_id() -> str:
    return uuid.uuid4().hex[:12]


def remember(chat_id: int, user_id: int, role: str, text: str, now: float | None = None,
             answer_id: str | None = None) -> None:
    if role not in {"user", "assistant"} or not text:
        return
    now = time.time() if now is None else now
    _prune((chat_id, user_id), now).append(
        {"ts": now, "role": role, "text": text[:MAX_CHARS], "answer_id": answer_id, "rating": None})


def set_rating(chat_id: int, user_id: int, answer_id: str, rating: int) -> None:
    for entry in _store.get((chat_id, user_id), ()):
        if entry.get("answer_id") == answer_id:
            entry["rating"] = rating


def forget(chat_id: int, user_id: int) -> None:
    _store.pop((chat_id, user_id), None)
    _hydrated.discard((chat_id, user_id))


# ---------------------------------------------------------------- database side (best effort)
async def hydrate(chat_id: int, user_id: int) -> None:
    """Load the last messages from the DB once per process, e.g. after a restart."""
    key = (chat_id, user_id)
    if key in _hydrated:
        return
    _hydrated.add(key)
    if _store.get(key):
        return
    try:
        from db.rpc import bot_ai_recent
        result = await bot_ai_recent(user_id, chat_id, MAX_MESSAGES)
        rows = result.data if not result.error and isinstance(result.data, list) else []
    except Exception as exc:
        logger.debug("ai memory hydrate failed: %s", exc)
        return
    window = _store[key]
    for row in rows:
        window.append({"ts": float(row.get("ts") or time.time()), "role": row.get("role"),
                       "text": str(row.get("content") or "")[:MAX_CHARS],
                       "answer_id": row.get("answer_id"), "rating": row.get("rating")})
    _prune(key, time.time())


async def persist(chat_id: int, user_id: int, role: str, text: str,
                  answer_id: str | None = None, agent: bool = False) -> None:
    try:
        from db.rpc import bot_ai_log_message
        await bot_ai_log_message(user_id, chat_id, role, text, answer_id, agent)
    except Exception as exc:
        logger.debug("ai memory persist failed: %s", exc)


async def rate(user_id: int, chat_id: int, answer_id: str, rating: int) -> bool:
    """Store 👍(1)/👎(-1); only the asker may rate. Works from RAM even if the DB is unavailable."""
    if rating not in (-1, 1) or not answer_id:
        return False
    set_rating(chat_id, user_id, answer_id, rating)
    try:
        from db.rpc import bot_ai_rate
        result = await bot_ai_rate(user_id, answer_id, rating)
        return bool(result.data) if not result.error else True
    except Exception as exc:
        logger.debug("ai rate failed: %s", exc)
        return True
