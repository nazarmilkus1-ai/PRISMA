import os
import sys
import unittest

# Добавляем путь к модулям, чтобы импортировать функции из bot.services.onboarding
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bot.services.onboarding import _display_name, _mention

class OnboardingTests(unittest.TestCase):
    def test_display_name_with_first_name(self):
        row = {"first_name": "John"}
        result = _display_name(row)
        self.assertEqual(result, "John")

    def test_display_name_with_full_name(self):
        row = {"full_name": "John Doe"}
        result = _display_name(row)
        self.assertEqual(result, "John Doe")

    def test_display_name_with_username(self):
        row = {"telegram_username": "john_doe"}
        result = _display_name(row)
        self.assertEqual(result, "john_doe")

    def test_display_name_without_name(self):
        row = {}
        result = _display_name(row)
        self.assertEqual(result, "участник")

    def test_display_name_with_spaces(self):
        row = {"first_name": "  John   "}
        result = _display_name(row)
        self.assertEqual(result, "John")

    def test_display_name_truncated(self):
        row = {"first_name": "ThisIsAVeryLongNameThatExceedsTheLimit"}
        result = _display_name(row)
        self.assertLessEqual(len(result), 32)

    def test_mention_with_valid_id(self):
        row = {"telegram_id": "123456789", "first_name": "John"}
        result = _mention(row)
        self.assertIn('<a href="tg://user?id=123456789">John</a>', result)

    def test_mention_with_invalid_id(self):
        row = {"telegram_id": "invalid"}
        result = _mention(row)
        self.assertEqual(result, "Ошибка: некорректный номер Telegram. Проверьте введённый ID.")

    def test_mention_with_empty_name(self):
        row = {"telegram_id": "123", "first_name": ""}
        result = _mention(row)
        self.assertIn('<a href="tg://user?id=123">участник</a>', result)


if __name__ == "__main__":
    unittest.main()
