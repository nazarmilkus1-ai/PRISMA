"""Тесты для TgIdValidation."""
import pytest
from services.validation import TgIdValidation


class TestTgIdValidation:
    """Проверка валидации Telegram ID."""

    def test_valid_user_id(self):
        """Обычный ID пользователя проходит проверку."""
        assert TgIdValidation.validate(123456789, "test") == 123456789

    def test_valid_chat_id(self):
        """ID чата (отрицательный) не проходит — только положительные."""
        with pytest.raises(ValueError):
            TgIdValidation.validate(-1001234567890, "test")

    def test_zero_is_invalid(self):
        """Ноль — невалидный ID."""
        with pytest.raises(ValueError):
            TgIdValidation.validate(0, "test")

    def test_negative_is_invalid(self):
        """Отрицательные числа — невалидные."""
        with pytest.raises(ValueError):
            TgIdValidation.validate(-1, "test")

    def test_none_is_invalid(self):
        """None — невалидный ID."""
        with pytest.raises(ValueError):
            TgIdValidation.validate(None, "test")

    def test_string_is_invalid(self):
        """Строка вместо числа — невалидная."""
        with pytest.raises(ValueError):
            TgIdValidation.validate("123456789", "test")  # type: ignore

    def test_max_safe_integer_valid(self):
        """Максимально безопасное целое (2^53-1) — валидно."""
        max_safe = 9_007_199_254_740_991
        assert TgIdValidation.validate(max_safe, "test") == max_safe

    def test_above_max_safe_invalid(self):
        """Число больше 2^53-1 — невалидно."""
        with pytest.raises(ValueError):
            TgIdValidation.validate(9_007_199_254_740_992, "test")

    def test_is_valid_returns_bool(self):
        """is_valid возвращает bool, не бросает исключение."""
        assert TgIdValidation.is_valid(123456789) is True
        assert TgIdValidation.is_valid(0) is False
        assert TgIdValidation.is_valid(-1) is False
        assert TgIdValidation.is_valid(None) is False
        assert TgIdValidation.is_valid(9_007_199_254_740_991) is True
        assert TgIdValidation.is_valid(9_007_199_254_740_992) is False

    def test_validate_optional_returns_none_for_none(self):
        """validate_optional пропускает None без ошибки."""
        assert TgIdValidation.validate_optional(None, "test") is None

    def test_validate_optional_validates_when_present(self):
        """validate_optional проверяет значение, если оно есть."""
        assert TgIdValidation.validate_optional(123456789, "test") == 123456789
        with pytest.raises(ValueError):
            TgIdValidation.validate_optional(0, "test")
