import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import quiz


class QuizParseTests(unittest.TestCase):
    def test_parse_valid_json(self):
        result = quiz.parse('{"question": "Какой блок самый твердый в Minecraft?", "options": ["Обсидиан", "Обсидиан2", "Обсидиан3", "Обсидиан4"], "correct": 0}')
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Какой блок самый твердый в Minecraft?")
        self.assertEqual(len(result["options"]), 4)
        self.assertEqual(result["correct"], 0)

    def test_parse_invalid_json(self):
        result = quiz.parse("not json at all")
        self.assertIsNone(result)

    def test_parse_missing_question(self):
        result = quiz.parse('{"options": ["A", "B", "C", "D"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_wrong_options_count(self):
        result = quiz.parse('{"question": "Test", "options": ["A", "B", "C"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_duplicate_options(self):
        result = quiz.parse('{"question": "Test", "options": ["A", "A", "C", "D"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_invalid_correct_index(self):
        result = quiz.parse('{"question": "Test", "options": ["A", "B", "C", "D"], "correct": 5}')
        self.assertIsNone(result)

    def test_parse_too_short_question(self):
        result = quiz.parse('{"question": "Ab", "options": ["A", "B", "C", "D"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_too_long_question(self):
        result = quiz.parse('{"question": "' + 'X' * 301 + '", "options": ["A", "B", "C", "D"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_empty_question(self):
        result = quiz.parse('{"question": "", "options": ["A", "B", "C", "D"], "correct": 0}')
        self.assertIsNone(result)


class QuizAllowedTests(unittest.TestCase):
    def test_allowed_first_question(self):
        # Reset module state before test to ensure clean slate
        quiz._last.pop(123456, None)
        quiz._day.pop(123456, None)
        result = quiz.allowed(123456)
        self.assertIsNone(result)

    def test_allowed_cooldown(self):
        quiz.remember_question(123456, "test")
        result1 = quiz.allowed(123456)
        result2 = quiz.allowed(123456)
        self.assertIsNone(result1)
        self.assertIsNotNone(result2)

    def test_allowed_daily_cap(self):
        for i in range(50):
            result = quiz.allowed(999999 + i)
            self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()