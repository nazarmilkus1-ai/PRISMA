import unittest
from utils.validation import TgIdValidation


class TgIdValidationTest(unittest.TestCase):
    """Tests for TgIdValidation class."""

    def test_valid_id(self):
        """Test valid Telegram ID (positive integer)."""
        result = TgIdValidation.validate(123456)
        self.assertTrue(result.is_valid)

    def test_zero_id(self):
        """Test zero Telegram ID."""
        result = TgIdValidation.validate(0)
        self.assertFalse(result.is_valid)

    def test_negative_id(self):
        """Test negative Telegram ID."""
        result = TgIdValidation.validate(-1)
        self.assertFalse(result.is_valid)

    def test_none_id(self):
        """Test None Telegram ID."""
        result = TgIdValidation.validate(None)
        self.assertFalse(result.is_valid)

    def test_float_id(self):
        """Test float Telegram ID."""
        result = TgIdValidation.validate(123.456)
        self.assertFalse(result.is_valid)

    def test_string_id(self):
        """Test string Telegram ID."""
        result = TgIdValidation.validate("123456")
        self.assertFalse(result.is_valid)

    def test_large_id(self):
        """Test large Telegram ID (2^53-1)."""
        result = TgIdValidation.validate(9007199254740991)
        self.assertTrue(result.is_valid)

    def test_too_large_id(self):
        """Test too large Telegram ID (2^53)."""
        result = TgIdValidation.validate(9007199254740992)
        self.assertFalse(result.is_valid)

    def test_validate_optional_valid(self):
        """Test validate_optional with valid ID."""
        result = TgIdValidation.validate_optional(123456)
        self.assertTrue(result.is_valid)

    def test_validate_optional_invalid(self):
        """Test validate_optional with invalid ID."""
        result = TgIdValidation.validate_optional(None)
        self.assertFalse(result.is_valid)

    def test_validate_optional_zero(self):
        """Test validate_optional with zero."""
        result = TgIdValidation.validate_optional(0)
        self.assertFalse(result.is_valid)

    def test_is_valid_method(self):
        """Test is_valid method."""
        validator = TgIdValidation(123456)
        self.assertTrue(validator.is_valid)

    def test_is_valid_false(self):
        """Test is_valid method with invalid ID."""
        validator = TgIdValidation(0)
        self.assertFalse(validator.is_valid)

    def test_boundary_id(self):
        """Test boundary ID values."""
        # Test that boundary values work correctly
        result = TgIdValidation.validate(1)
        self.assertTrue(result.is_valid)
        result = TgIdValidation.validate(-1)
        self.assertFalse(result.is_valid)


if __name__ == "__main__":
    unittest.main()
