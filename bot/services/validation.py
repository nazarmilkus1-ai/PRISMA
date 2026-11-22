"""Централизованная валидация Telegram ID."""
from __future__ import annotations

import logging

log = logging.getLogger(__name__)

# Telegram ID — положительное число, обычно до 2^53 (безопасный диапазон JS)
# Реальные ID пользователей и чатов в Telegram укладываются в 64 бита со знаком.
# Боты получают update.message.from_user.id — это int > 0.
MIN_TG_ID = 1
MAX_TG_ID = 9_007_199_254_740_991  # 2^53 - 1, Number.MAX_SAFE_INTEGER


class TgIdValidation:
    """Валидация Telegram ID с логированием некорректных значений."""

    @staticmethod
    def is_valid(tg_id: int | None) -> bool:
        """Проверить, что tg_id — корректный Telegram ID."""
        if tg_id is None:
            return False
        if not isinstance(tg_id, int):
            return False
        return MIN_TG_ID <= tg_id <= MAX_TG_ID

    @staticmethod
    def validate(tg_id: int | None, context: str = "") -> int:
        """
        Проверить и вернуть tg_id, либо поднять ValueError с понятным сообщением.
        context — где вызывается (для логов).
        """
        if not TgIdValidation.is_valid(tg_id):
            log.warning("Невалидный Telegram ID: %r (контекст: %s)", tg_id, context)
            raise ValueError(f"Некорректный Telegram ID: {tg_id}")
        return tg_id

    @staticmethod
    def validate_optional(tg_id: int | None, context: str = "") -> int | None:
        """Проверить tg_id, если он передан; None пропускает без ошибки."""
        if tg_id is None:
            return None
        return TgIdValidation.validate(tg_id, context)
