import unittest
from utils.validation import Validation


class TgIdValidationTest(unittest.TestCase):
    def test_valid_user_ids(self):
        ok, err = Validation.validate_telegram_id(123456789)
        self.assertTrue(ok)
        self.assertIsNone(err)

        ok, err = Validation.validate_telegram_id(999999999999)
        self.assertTrue(ok)
        self.assertIsNone(err)

        # Максимальный безопасный integer в JavaScript (2^53 - 1)
        ok, err = Validation.validate_telegram_id(9007199254740991)
        self.assertTrue(ok)
        self.assertIsNone(err)

    def test_invalid_user_ids(self):
        ok, err = Validation.validate_telegram_id(0)
        self.assertFalse(ok)
        self.assertIsNotNone(err)

        ok, err = Validation.validate_telegram_id(-1)
        self.assertFalse(ok)
        self.assertIsNotNone(err)

        ok, err = Validation.validate_telegram_id(None)
        self.assertFalse(ok)
        self.assertIsNotNone(err)

        ok, err = Validation.validate_telegram_id(1.5)
        self.assertFalse(ok)
        self.assertIsNotNone(err)

        ok, err = Validation.validate_telegram_id("123")
        self.assertFalse(ok)
        self.assertIsNotNone(err)

        # 2^53 — больше максимального безопасного integer
        ok, err = Validation.validate_telegram_id(9007199254740992)
        self.assertFalse(ok)
        self.assertIsNotNone(err)

    def test_validate_optional(self):
        ok, err = Validation.validate_telegram_id(None, "test")
        self.assertFalse(ok)
        self.assertIsNotNone(err)

    def test_is_valid(self):
        self.assertTrue(Validation.is_valid(123456789))
        self.assertFalse(Validation.is_valid(0))
        self.assertFalse(Validation.is_valid(-1))
        self.assertFalse(Validation.is_valid(None))
        self.assertFalse(Validation.is_valid("123"))
        self.assertTrue(Validation.is_valid(9007199254740991))
        self.assertFalse(Validation.is_valid(9007199254740992))


if __name__ == "__main__":
    unittest.main()
