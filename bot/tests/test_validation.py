import unittest
from utils.validation import Validation


class TgIdValidationTest(unittest.TestCase):
    """Тесты валидации Telegram ID."""

    def test_valid_id(self):
        """Валидный ID должен проходить проверку."""
        ok, _ = Validation.validate_telegram_id(123456789)
        self.assertTrue(ok)

    def test_zero_id(self):
        """ID равный нулю должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id(0)
        self.assertFalse(ok)

    def test_negative_id(self):
        """Отрицательный ID должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id(-1)
        self.assertFalse(ok)

    def test_none_id(self):
        """None ID должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id(None)
        self.assertFalse(ok)

    def test_float_id(self):
        """Float ID должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id(123.456)
        self.assertFalse(ok)

    def test_string_id(self):
        """Строковый ID должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id("123456789")
        self.assertFalse(ok)

    def test_large_id(self):
        """ID больше 2^53-1 должен быть невалидным."""
        ok, _ = Validation.validate_telegram_id(9007199254740992)
        self.assertFalse(ok)

    def test_validate_method(self):
        """Метод validate должен работать корректно."""
        self.assertIsInstance(Validation.validate_telegram_id(123456789), tuple)

    def test_validate_optional_method(self):
        """Метод validate_optional должен работать корректно."""
        ok, _ = Validation.validate_telegram_id(None, optional=True)
        self.assertTrue(ok)

    def test_is_valid_method(self):
        """Метод is_valid должен работать корректно."""
        self.assertTrue(Validation.is_valid_telegram_id(123456789))

    def test_is_valid_false(self):
        """is_valid должен возвращать False для невалидного ID."""
        self.assertFalse(Validation.is_valid_telegram_id(0))

    def test_boundary_id(self):
        """Граничное значение 2^53-1 должно быть валидным."""
        ok, _ = Validation.validate_telegram_id(9007199254740991)
        self.assertTrue(ok)

    def test_boundary_id_plus_one(self):
        """Значение выше границы должно быть невалидным."""
        ok, _ = Validation.validate_telegram_id(9007199254740992)
        self.assertFalse(ok)
