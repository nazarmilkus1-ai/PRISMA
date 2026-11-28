import unittest
from services import quiz

class QuizNewTests(unittest.TestCase):
    def test_parse_valid(self):
        raw = "{\"question\": \"Какой цвет трава?\", \"options\": [\"Зеленый\", \"Синий\", \"Красный\", \"Желтый\"], \"correct\": 0, \"explanation\": \"Трава зеленая\"}"
        result = quiz.parse(raw)
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Какой цвет трава?")
        self.assertEqual(len(result["options"]), 4)
        self.assertEqual(result["correct"], 0)

    def test_parse_invalid_json(self):
        self.assertIsNone(quiz.parse("not json"))
        self.assertIsNone(quiz.parse("{invalid}"))

    def test_parse_wrong_options_count(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два"], "correct": 0}')
        self.assertIsNone(result)
