"""One PRISMA profile, several accounts.

* A second Minecraft account on the OTHER platform (Java + Bedrock) shares stats, clan, punishments and playtime
  because the plugin resolves it to the same profile; the plugin refuses two accounts online at once.
* A second Telegram account acts as the same profile in the bot's private chat. It is linked with a one-time
  code, so nobody can attach an account to somebody else's profile.
"""
from __future__ import annotations

import secrets
import time

from db.rpc import bot_telegram_alias_resolve

CODE_TTL = 600.0
ALIAS_CACHE_TTL = 120.0
_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

_codes: dict[str, tuple[int, float]] = {}
_alias_cache: dict[int, tuple[int | None, float]] = {}

MINECRAFT_ERRORS = {
    "USER_NOT_FOUND": "Профиль не найден.",
    "NOT_ACCEPTED": "Второй аккаунт можно добавить после одобрения заявки.",
    "BANNED": "Профиль заблокирован.",
    "SAME_PLATFORM": "Второй аккаунт должен быть на другой платформе: у вас Java — добавьте Bedrock, и наоборот.",
    "NICKNAME_TAKEN": "Этот ник уже занят.",
    "ACCOUNT_LIMIT": "Второй аккаунт уже добавлен. Сначала уберите его: /removeaccount",
    "INVALID_PLATFORM": "Платформа: java или bedrock.",
    "INVALID_MINECRAFT_NICK": "Ник не подходит. Java: 3–16 символов (латиница, цифры, «_»). Bedrock: Gamertag до 15 символов, пробелы можно.",
}
TELEGRAM_ERRORS = {
    "INVALID_ACCOUNT": "Нельзя привязать этот аккаунт.",
    "PRIMARY_NOT_ACCEPTED": "Основной профиль должен быть одобрен.",
    "ALIAS_HAS_OWN_PROFILE": "У этого Telegram-аккаунта уже есть свой профиль PRISMA, привязать его нельзя.",
    "ALIAS_ALREADY_LINKED": "Этот Telegram-аккаунт уже привязан.",
    "ALIAS_LIMIT": "К профилю уже привязан второй Telegram-аккаунт. Сначала: /removetg",
}


def new_code(primary_tg: int, now: float | None = None) -> str:
    now = time.time() if now is None else now
    for code in [c for c, (_, exp) in _codes.items() if exp <= now]:
        _codes.pop(code, None)
    for code, (owner, _) in list(_codes.items()):
        if owner == primary_tg:
            _codes.pop(code, None)  # one live code per profile
    code = "".join(secrets.choice(_ALPHABET) for _ in range(8))
    _codes[code] = (primary_tg, now + CODE_TTL)
    return code


def take_code(code: str, now: float | None = None) -> int | None:
    """Single use: returns the primary telegram id, or None if unknown or expired."""
    now = time.time() if now is None else now
    entry = _codes.pop((code or "").strip().upper(), None)
    if not entry or entry[1] <= now:
        return None
    return entry[0]


def forget(tg_id: int | None = None) -> None:
    if tg_id is None:
        _alias_cache.clear()
    else:
        _alias_cache.pop(tg_id, None)


async def primary_for(tg_id: int, now: float | None = None) -> int | None:
    """The primary Telegram id when tg_id is a linked second account, else None. Cached, failure-tolerant."""
    now = time.time() if now is None else now
    hit = _alias_cache.get(tg_id)
    if hit and hit[1] > now:
        return hit[0]
    try:
        result = await bot_telegram_alias_resolve(tg_id)
    except Exception:
        return None
    if result.error:
        return None
    try:
        primary = int(result.data) if result.data not in (None, "") else None
    except (TypeError, ValueError):
        primary = None
    _alias_cache[tg_id] = (primary, now + ALIAS_CACHE_TTL)
    return primary
