"""Тесты для TgIdValidation."""
import unittest
from services.validation import TgIdValidation


class TestTgIdValidation(unittest.TestCase):
    def test_valid_ids(self):
        """Корректные Telegram ID проходят валидацию."""
        valid_ids = [1, 123, 999999999, 9_007_199_254_740_991]
        for tg_id in valid_ids:
            with self.subTest(tg_id=tg_id):
                self.assertTrue(TgIdValidation.is_valid(tg_id))
                self.assertEqual(TgIdValidation.validate(tg_id, "test"), tg_id)
                self.assertEqual(TgIdValidation.validate_optional(tg_id, "test"), tg_id)

    def test_invalid_ids(self):
        """Некорректные Telegram ID не проходят валидацию."""
        invalid_ids = [0, -1, -100, 9_007_199_254_740_992, None, "123", 1.5]
        for tg_id in invalid_ids:
            with self.subTest(tg_id=tg_id):
                self.assertFalse(TgIdValidation.is_valid(tg_id))
                with self.assertRaises(ValueError):
                    TgIdValidation.validate(tg_id, "test")
                if tg_id is None:
                    self.assertIsNone(TgIdValidation.validate_optional(tg_id, "test"))
                else:
                    with self.assertRaises(ValueError):
                        TgIdValidation.validate_optional(tg_id, "test")

    def test_validate_optional_none(self):
        """validate_optional пропускает None без ошибки."""
        self.assertIsNone(TgIdValidation.validate_optional(None, "test"))

    def test_validate_optional_valid(self):
        """validate_optional возвращает валидный ID."""
        self.assertEqual(TgIdValidation.validate_optional(12345, "test"), 12345)

if __name__ == "__main__":
    unittest.main()
