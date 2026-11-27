import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import quiz


class QuizNewTests(unittest.TestCase):
    def test_parse_empty_string(self):
        self.assertIsNone(quiz.parse(""))
        self.assertIsNone(quiz.parse("   "))

    def test_parse_no_json(self):
        self.assertIsNone(quiz.parse("just a random string"))
        self.assertIsNone(quiz.parse("not json at all"))

    def test_parse_invalid_json_format(self):
        self.assertIsNone(quiz.parse("{invalid json}"))
        self.assertIsNone(quiz.parse("{\"key\": value}"))

    def test_parse_missing_question(self):
        result = quiz.parse('{"options": ["Один", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_missing_options(self):
        result = quiz.parse('{"question": "Какой цвет трава?", "correct": 0}')
        self.assertIsNone(result)

    def test_parse_invalid_correct_type(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"], "correct": "0"}')
        self.assertIsNone(result)

    def test_parse_invalid_correct_out_of_range(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"], "correct": 5}')
        self.assertIsNone(result)

    def test_parse_invalid_options_count(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_duplicate_options(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Один", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_short_question(self):
        result = quiz.parse('{"question": "Кто?", "options": ["Один", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_long_question(self):
        long_question = "A" * 301
        result = quiz.parse('{"question": "' + long_question + '", "options": ["Один", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_short_option(self):
        result = quiz.parse('{"question": "Тест", "options": ["", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_long_option(self):
        long_option = "A" * 101
        result = quiz.parse('{"question": "Тест", "options": ["' + long_option + '", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_valid_with_explanation(self):
        result = quiz.parse('{"question": "Какой цвет трава?", "options": ["Один", "Два", "Три", "Четыре"], "correct": 1, "explanation": "Правильный ответ"}')
        self.assertIsNotNone(result)
        self.assertEqual(result["explanation"], "Правильный ответ")

if __name__ == "__main__":
    unittest.main()
