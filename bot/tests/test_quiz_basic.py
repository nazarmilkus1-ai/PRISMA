import unittest
from services import quiz

class QuizTests(unittest.TestCase):
    def test_parse_valid(self):
        raw = "{\"question\": \"test\", \"options\": [\"A\", \"B\", \"C\", \"D\"], \"correct\": 0}"
        result = quiz.parse(raw)
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "test")
        self.assertEqual(len(result["options"]), 4)

    def test_parse_invalid_json(self):
        self.assertIsNone(quiz.parse("not json"))
        self.assertIsNone(quiz.parse("{invalid}"))