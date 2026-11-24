"""Тесты для TgIdValidation."""
import pytest

from services.validation import TgIdValidation


class TestTgIdValidation:
    """Проверки валидации Telegram ID."""

    def test_valid_user_id(self):
        """Обычный ID пользователя проходит."""
        assert TgIdValidation.is_valid(123456789) is True
        assert TgIdValidation.validate(123456789, "test") == 123456789

    def test_valid_chat_id(self):
        """Отрицательный ID чата (супергруппа) — невалиден для наших целей."""
        assert TgIdValidation.is_valid(-1001234567890) is False

    def test_zero_invalid(self):
        """Ноль невалиден."""
        assert TgIdValidation.is_valid(0) is False

    def test_negative_invalid(self):
        """Отрицательные числа невалидны."""
        assert TgIdValidation.is_valid(-1) is False

    def test_none_invalid(self):
        """None невалиден."""
        assert TgIdValidation.is_valid(None) is False

    def test_float_invalid(self):
        """Числа с точкой невалидны."""
        assert TgIdValidation.is_valid(123.45) is False

    def test_string_invalid(self):
        """Строки невалидны."""
        assert TgIdValidation.is_valid("123456789") is False

    def test_max_safe_integer_valid(self):
        """Максимально безопасное целое (2^53-1) валидно."""
        assert TgIdValidation.is_valid(9_007_199_254_740_991) is True

    def test_over_max_invalid(self):
        """Число больше 2^53-1 невалидно."""
        assert TgIdValidation.is_valid(9_007_199_254_740_992) is False

    def test_validate_raises_on_invalid(self):
        """validate поднимает ValueError на невалидном ID."""
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(0, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(-1, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(None, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(123.45, "test")

    def test_validate_optional_none_returns_none(self):
        """validate_optional(None) возвращает None без ошибки."""
        assert TgIdValidation.validate_optional(None, "test") is None

    def test_validate_optional_valid_returns_value(self):
        """validate_optional с валидным ID возвращает его."""
        assert TgIdValidation.validate_optional(123456789, "test") == 123456789

    def test_validate_optional_invalid_raises(self):
        """validate_optional с невалидным ID поднимает ValueError."""
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate_optional(0, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate_optional(-1, "test")