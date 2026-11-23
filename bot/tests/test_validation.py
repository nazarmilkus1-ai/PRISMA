"""Тесты для TgIdValidation."""
import pytest
from services.validation import TgIdValidation


class TestTgIdValidation:
    """Проверки валидации Telegram ID."""

    def test_valid_positive_ids(self):
        """Обычные положительные ID должны проходить."""
        assert TgIdValidation.is_valid(1) is True
        assert TgIdValidation.is_valid(123456789) is True
        assert TgIdValidation.is_valid(9_007_199_254_740_991) is True  # MAX_SAFE_INTEGER

    def test_invalid_zero_and_negative(self):
        """Ноль и отрицательные числа невалидны."""
        assert TgIdValidation.is_valid(0) is False
        assert TgIdValidation.is_valid(-1) is False
        assert TgIdValidation.is_valid(-100) is False

    def test_invalid_none_and_non_int(self):
        """None и не-числа невалидны."""
        assert TgIdValidation.is_valid(None) is False
        assert TgIdValidation.is_valid("123") is False
        assert TgIdValidation.is_valid(123.45) is False
        assert TgIdValidation.is_valid([]) is False

    def test_validate_returns_id_on_success(self):
        """validate возвращает ID, если он корректен."""
        assert TgIdValidation.validate(12345, "test") == 12345
        assert TgIdValidation.validate(1, "test") == 1

    def test_validate_raises_on_invalid(self):
        """validate поднимает ValueError на невалидных ID."""
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(0, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(-1, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate(None, "test")
        with pytest.raises(ValueError, match="Некорректный Telegram ID"):
            TgIdValidation.validate("123", "test")

    def test_validate_optional_returns_none_for_none(self):
        """validate_optional пропускает None без ошибки."""
        assert TgIdValidation.validate_optional(None, "test") is None

    def test_validate_optional_validates_when_present(self):
        """validate_optional проверяет значение, если оно есть."""
        assert TgIdValidation.validate_optional(12345, "test") == 12345
        with pytest.raises(ValueError):
            TgIdValidation.validate_optional(0, "test")
        with pytest.raises(ValueError):
            TgIdValidation.validate_optional(-1, "test")

    def test_max_safe_integer_boundary(self):
        """Граница MAX_SAFE_INTEGER (2^53 - 1)."""
        max_safe = 9_007_199_254_740_991
        assert TgIdValidation.is_valid(max_safe) is True
        assert TgIdValidation.is_valid(max_safe + 1) is False
