"""User-safe error presentation for PRISMA bot handlers.

Technical exceptions and transport errors must never be shown to users verbatim.
Known business error codes may be mapped to stable Russian messages.
"""

from __future__ import annotations

from typing import Any

ERROR_MESSAGES: dict[str, str] = {
    "ADMIN_LACKS_PERMISSION": "Недостаточно прав.",
    "PERMISSION_DENIED": "Недостаточно прав.",
    "USER_NOT_FOUND": "Профиль PRISMA не найден.",
    "PLAYER_NOT_FOUND": "Игрок не найден.",
    "CLAN_NOT_FOUND": "Клан не найден.",
    "NO_CLAN": "Вы не состоите в клане.",
    "USER_ALREADY_IN_CLAN": "Вы уже состоите в клане.",
    "NO_CLAN_PERMISSION": "Недостаточно прав в клане.",
    "OWNER_ONLY": "Это действие доступно только владельцу клана.",
    "INVITE_NOT_FOUND": "Приглашение не найдено или уже недействительно.",
    "REPORT_NOT_FOUND": "Репорт не найден.",
    "REPORT_ALREADY_CLOSED": "Репорт уже закрыт.",
    "INVALID_REPORT_STATUS": "Неизвестный статус репорта.",
    "APPEAL_NOT_FOUND": "Апелляция не найдена.",
    "APPEAL_ALREADY_CLOSED": "Апелляция уже закрыта.",
    "USER_NOT_ALLOWED": "Действие недоступно для этого аккаунта.",
    "INVALID_ROLE": "Укажите корректную роль.",
    "ROLE_UNCHANGED": "У игрока уже установлена эта роль.",
    "DAILY_LIMIT": "Дневной лимит обращений уже использован.",
    "INVALID_MESSAGE": "Некорректное сообщение.",
    "INVALID_REASON": "Некорректная причина.",
    "CANNOT_REPORT_SELF": "Нельзя пожаловаться на самого себя.",
    "DUPLICATE_OPEN_REPORT": "У вас уже есть открытая жалоба на этого игрока.",
    "SESSION_NOT_FOUND": "Ссылка для входа недействительна. Запросите новую в панели.",
    "SESSION_EXPIRED": "Ссылка для входа устарела. Запросите новую в панели.",
}

def _code(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip().upper()

def safe_rpc_error(result: Any, fallback: str = "Не удалось выполнить действие.") -> str:
    """Return a stable user-facing Russian message; never expose raw RPC/DB text."""
    data = getattr(result, "data", None)
    data_error = data.get("error") if isinstance(data, dict) else None
    for candidate in (data_error, getattr(result, "error", None)):
        code = _code(candidate)
        if code in ERROR_MESSAGES:
            return ERROR_MESSAGES[code]
    return fallback
