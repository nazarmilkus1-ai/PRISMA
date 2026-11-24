import pytest
from utils.validation import Validation


class TestValidateTelegramId:
    """Тесты для validate_telegram_id."""

    def test_valid_positive_int(self):
        ok, err = Validation.validate_telegram_id(123456789)
        assert ok is True
        assert err is None

    def test_valid_large_int(self):
        ok, err = Validation.validate_telegram_id(999999999999)
        assert ok is True
        assert err is None

    def test_zero_is_invalid(self):
        ok, err = Validation.validate_telegram_id(0)
        assert ok is False
        assert err is not None

    def test_negative_is_invalid(self):
        ok, err = Validation.validate_telegram_id(-123)
        assert ok is False
        assert err is not None

    def test_float_is_invalid(self):
        ok, err = Validation.validate_telegram_id(123.45)
        assert ok is False
        assert err is not None

    def test_string_is_invalid(self):
        ok, err = Validation.validate_telegram_id("123456")
        assert ok is False
        assert err is not None

    def test_none_is_invalid(self):
        ok, err = Validation.validate_telegram_id(None)
        assert ok is False
        assert err is not None

    def test_custom_context_in_error(self):
        ok, err = Validation.validate_telegram_id(-1, "Мой ID")
        assert ok is False
        assert "мой id" in err.lower()


class TestValidateUuid:
    """Тесты для validate_uuid."""

    def test_valid_uuid(self):
        ok, err = Validation.validate_uuid("550e8400-e29b-41d4-a716-446655440000")
        assert ok is True
        assert err is None

    def test_valid_uuid_uppercase(self):
        ok, err = Validation.validate_uuid("550E8400-E29B-41D4-A716-446655440000")
        assert ok is True
        assert err is None

    def test_invalid_uuid_format(self):
        ok, err = Validation.validate_uuid("not-a-uuid")
        assert ok is False
        assert err is not None

    def test_empty_string_invalid(self):
        ok, err = Validation.validate_uuid("")
        assert ok is False
        assert err is not None

    def test_none_invalid(self):
        ok, err = Validation.validate_uuid(None)
        assert ok is False
        assert err is not None

    def test_custom_context(self):
        ok, err = Validation.validate_uuid("bad", "Player UUID")
        assert ok is False
        assert "player uuid" in err.lower()


class TestValidateMinecraftNick:
    """Тесты для validate_minecraft_nick."""

    def test_valid_java_nick(self):
        ok, err = Validation.validate_minecraft_nick("Player123", "java")
        assert ok is True
        assert err is None

    def test_valid_java_nick_underscore(self):
        ok, err = Validation.validate_minecraft_nick("Player_123", "java")
        assert ok is True
        assert err is None

    def test_java_nick_too_short(self):
        ok, err = Validation.validate_minecraft_nick("Ab", "java")
        assert ok is False
        assert err is not None

    def test_java_nick_too_long(self):
        ok, err = Validation.validate_minecraft_nick("A" * 17, "java")
        assert ok is False
        assert err is not None

    def test_java_nick_invalid_chars(self):
        ok, err = Validation.validate_minecraft_nick("Player-123", "java")
        assert ok is False
        assert err is not None

    def test_valid_bedrock_nick(self):
        ok, err = Validation.validate_minecraft_nick("Player 123", "bedrock")
        assert ok is True
        assert err is None

    def test_bedrock_nick_with_underscore(self):
        ok, err = Validation.validate_minecraft_nick("Player_123", "bedrock")
        assert ok is True
        assert err is None

    def test_bedrock_nick_too_long(self):
        ok, err = Validation.validate_minecraft_nick("A" * 16, "bedrock")
        assert ok is False
        assert err is not None

    def test_auto_detect_java(self):
        ok, err = Validation.validate_minecraft_nick("Player123")
        assert ok is True
        assert err is None

    def test_auto_detect_bedrock(self):
        ok, err = Validation.validate_minecraft_nick("Player 123")
        assert ok is True
        assert err is None

    def test_empty_nick_invalid(self):
        ok, err = Validation.validate_minecraft_nick("")
        assert ok is False
        assert err is not None

    def test_whitespace_only_invalid(self):
        ok, err = Validation.validate_minecraft_nick("   ")
        assert ok is False
        assert err is not None

    def test_none_invalid(self):
        ok, err = Validation.validate_minecraft_nick(None)
        assert ok is False
        assert err is not None


class TestValidateText:
    """Тесты для validate_text."""

    def test_valid_text(self):
        ok, err = Validation.validate_text("Hello world")
        assert ok is True
        assert err is None

    def test_too_short(self):
        ok, err = Validation.validate_text("Hi", min_length=5)
        assert ok is False
        assert err is not None

    def test_too_long(self):
        ok, err = Validation.validate_text("A" * 1001, max_length=1000)
        assert ok is False
        assert err is not None

    def test_not_a_string(self):
        ok, err = Validation.validate_text(123)
        assert ok is False
        assert err is not None

    def test_whitespace_stripped(self):
        ok, err = Validation.validate_text("  Hello  ", min_length=5)
        assert ok is True
        assert err is None

    def test_custom_context(self):
        ok, err = Validation.validate_text("", context="Комментарий")
        assert ok is False
        assert "комментарий" in err.lower()
