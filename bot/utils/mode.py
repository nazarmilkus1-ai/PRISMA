from __future__ import annotations

from typing import Optional

from redis.asyncio import Redis


PARTICIPANT_MODE = "participant"
ADMIN_MODE = "admin"
MODE_KEY_PREFIX = "prisma:bot:mode:"
MODE_TTL_SECONDS = 30 * 24 * 60 * 60

_redis: Optional[Redis] = None
_memory_modes: dict[int, str] = {}


async def configure_mode_store(redis: Optional[Redis]) -> None:
    """Use the same Redis connection as aiogram when available.

    A small in-memory fallback keeps local development working when Redis is
    intentionally unavailable. The effective default is still computed from
    live permissions by utils.permissions.
    """
    global _redis
    _redis = redis


def _key(tg_id: int) -> str:
    return f"{MODE_KEY_PREFIX}{tg_id}"


async def get_mode(tg_id: int) -> str | None:
    if _redis is not None:
        try:
            value = await _redis.get(_key(tg_id))
            if value in {PARTICIPANT_MODE, ADMIN_MODE}:
                return value
        except Exception:
            # Mode is UI state. If Redis is temporarily unavailable, callers
            # can safely fall back to the permission-derived default.
            pass
    value = _memory_modes.get(tg_id)
    return value if value in {PARTICIPANT_MODE, ADMIN_MODE} else None


async def set_mode(tg_id: int, mode: str) -> None:
    if mode not in {PARTICIPANT_MODE, ADMIN_MODE}:
        raise ValueError(f"Unknown bot mode: {mode}")

    _memory_modes[tg_id] = mode
    if _redis is not None:
        try:
            await _redis.set(_key(tg_id), mode, ex=MODE_TTL_SECONDS)
        except Exception:
            # The in-memory value still lets the current process continue.
            pass


async def clear_mode(tg_id: int) -> None:
    _memory_modes.pop(tg_id, None)
    if _redis is not None:
        try:
            await _redis.delete(_key(tg_id))
        except Exception:
            pass
