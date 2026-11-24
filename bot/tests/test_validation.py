import unittest

from utils.validation import Validation


class ValidationTests(unittest.TestCase):
    def test_validate_uuid_valid(self):
        ok, error = Validation.validate_uuid("123e4567-e89b-12d3-a456-426614174000")
        self.assertTrue(ok)
        self.assertIsNone(error)

    def test_validate_uuid_valid_with_dashes(self):
        ok, error = Validation.validate_uuid("550e8400-e29b-41d4-a716-446655440000")
        self.assertTrue(ok)
        self.assertIsNone(error)

    def test_validate_uuid_invalid_format(self):
        ok, error = Validation.validate_uuid("not-a-uuid")
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_uuid_empty_string(self):
        ok, error = Validation.validate_uuid("")
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_uuid_none(self):
        ok, error = Validation.validate_uuid(None)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_uuid_non_string(self):
        ok, error = Validation.validate_uuid(123)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_text_valid(self):
        ok, error = Validation.validate_text("Hello world")
        self.assertTrue(ok)
        self.assertIsNone(error)

    def test_validate_text_min_length(self):
        ok, error = Validation.validate_text("Hi", min_length=5)
        self.assertFalse(ok)
        self.assertIn("минимум 5", error)

    def test_validate_text_max_length(self):
        ok, error = Validation.validate_text("Hello world", max_length=5)
        self.assertFalse(ok)
        self.assertIn("максимум 5", error)

    def test_validate_text_empty(self):
        ok, error = Validation.validate_text("")
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_text_whitespace_only(self):
        ok, error = Validation.validate_text("   ")
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_text_non_string(self):
        ok, error = Validation.validate_text(123)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_telegram_id_valid(self):
        ok, error = Validation.validate_telegram_id(123456789)
        self.assertTrue(ok)
        self.assertIsNone(error)

    def test_validate_telegram_id_zero(self):
        ok, error = Validation.validate_telegram_id(0)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_telegram_id_negative(self):
        ok, error = Validation.validate_telegram_id(-1)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_telegram_id_non_int(self):
        ok, error = Validation.validate_telegram_id("123456789")
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_telegram_id_float(self):
        ok, error = Validation.validate_telegram_id(123.45)
        self.assertFalse(ok)
        self.assertIsNotNone(error)

    def test_validate_telegram_id_none(self):
        ok, error = Validation.validate_telegram_id(None)
        self.assertFalse(ok)
        self.assertIsNotNone(error)


if __name__ == "__main__":
    unittest.main()
