import unittest

from services.validation import TgIdValidation


class TgIdValidationTests(unittest.TestCase):
    def test_valid_telegram_ids(self):
        """Корректные Telegram ID должны проходить валидацию."""
        valid_ids = [1, 123, 999999999, 9007199254740991]  # MAX_TG_ID
        for tg_id in valid_ids:
            self.assertTrue(TgIdValidation.is_valid(tg_id), f"ID {tg_id} должен быть валидным")
            self.assertEqual(TgIdValidation.validate(tg_id, "test"), tg_id)

    def test_invalid_telegram_ids(self):
        """Некорректные Telegram ID должны не проходить валидацию."""
        invalid_ids = [0, -1, -100, 9007199254740992, 99999999999999999, None, "123", 1.5]
        for tg_id in invalid_ids:
            self.assertFalse(TgIdValidation.is_valid(tg_id), f"ID {tg_id} не должен быть валидным")
            with self.assertRaises(ValueError):
                TgIdValidation.validate(tg_id, "test")

    def test_validate_optional(self):
        """validate_optional должен пропускать None и валидировать остальные."""
        self.assertIsNone(TgIdValidation.validate_optional(None, "test"))
        self.assertEqual(TgIdValidation.validate_optional(123, "test"), 123)
        with self.assertRaises(ValueError):
            TgIdValidation.validate_optional(0, "test")
        with self.assertRaises(ValueError):
            TgIdValidation.validate_optional(-1, "test")


if __name__ == "__main__":
    unittest.main()
