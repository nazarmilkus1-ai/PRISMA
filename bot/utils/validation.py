# utils/validation.py
"""
Централизованная валидация Telegram ID.

Telegram ID — это положительное целое число до 2^53-1 (Number.MAX_SAFE_INTEGER в JS).
Большие значения могут прийти из некорректных источников или ошибок интеграции.
"""
import logging
from typing import Optional

log = logging.getLogger(__name__)

# Telegram использует 64-битные signed integers, но безопасный диапазон для JS — до 2^53-1
TG_ID_MAX = 2**53 - 1  # 9007199254740991


class TgIdValidation:
    """Валидация Telegram ID."""

    @staticmethod
    def is_valid(tg_id: Optional[int]) -> bool:
        """Проверить, что tg_id — корректный Telegram ID."""
        if tg_id is None:
            return False
        if not isinstance(tg_id, int):
            return False
        if tg_id <= 0:
            return False
        if tg_id > TG_ID_MAX:
            return False
        return True

    @staticmethod
    def validate(tg_id: Optional[int], field_name: str = "Telegram ID") -> int:
        """
        Проверить и вернуть tg_id, либо поднять ValueError с понятным сообщением.
        Используй там, где невалидный ID — это ошибка вызывающего кода.
        """
        if not TgIdValidation.is_valid(tg_id):
            raise ValueError(f"{field_name} должен быть положительным целым числом до {TG_ID_MAX}, получено: {tg_id}")
        return tg_id

    @staticmethod
    def validate_optional(tg_id: Optional[int], field_name: str = "Telegram ID") -> Optional[int]:
        """
        Проверить tg_id, если он передан. None возвращается как есть.
        Удобно для опциональных полей.
        """
        if tg_id is None:
            return None
        return TgIdValidation.validate(tg_id, field_name)