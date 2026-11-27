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
        result = quiz.parse('{"question": "Какой цвет трава?", "options": ["Зеленый", "Синий", "Красный", "Желтый"], "correct": 0, "explanation": "Трава зеленая"}')
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Какой цвет трава?")
        self.assertEqual(result["options"], ["Зеленый", "Синий", "Красный", "Желтый"])
        self.assertEqual(result["correct"], 0)

    def test_parse_invalid_json(self):
        self.assertIsNone(quiz.parse("not json at all"))
        self.assertIsNone(quiz.parse("{invalid"))

    def test_parse_wrong_options_count(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_wrong_correct_index(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"], "correct": 5}')
        self.assertIsNone(result)

    def test_parse_question_too_short(self):
        result = quiz.parse('{"question": "Короткий", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_question_too_long(self):
        long_question = "A" * 301
        result = quiz.parse('{"question": "' + long_question + '", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_duplicate_options(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Один", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_valid_with_explanation(self):
        result = quiz.parse('{"question": "Какой цвет трава?", "options": ["Один", "Два", "Три", "Четыре"], "correct": 1, "explanation": "Правильный ответ"}')
        self.assertIsNotNone(result)
        self.assertEqual(result["explanation"], "Правильный ответ")

    def test_parse_missing_question(self):
        result = quiz.parse('{"options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_empty_question(self):
        result = quiz.parse('{"question": "", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_empty_options(self):
        result = quiz.parse('{"question": "Тест", "options": [], "correct": 0}')
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()