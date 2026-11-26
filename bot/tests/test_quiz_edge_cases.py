import os
import sys
import unittest
import json

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import quiz


class QuizEdgeCaseTests(unittest.TestCase):
    def test_parse_empty_question(self):
        result = quiz.parse('{"question": "", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_single_option(self):
        result = quiz.parse('{"question": "Тест", "options": ["Единственный"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_options_with_special_chars(self):
        result = quiz.parse('{"question": "Тест с спецchars: !@#$%", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Тест с спецchars: !@#$%")

    def test_parse_correct_index_zero_based(self):
        result = quiz.parse('{"question": "Тестовый вопрос", "options": ["Правильный", "Неправильный", "Вариант 3", "Вариант 4"], "correct": 0}')
        self.assertIsNotNone(result)
        self.assertEqual(result["correct"], 0)

    def test_parse_all_options_correct(self):
        result = quiz.parse('{"question": "Тестовый вопрос", "options": ["a", "b", "c", "d"], "correct": 3}')
        self.assertIsNotNone(result)

    def test_parse_missing_correct_field(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"]}')
        self.assertIsNone(result)

    def test_parse_correct_out_of_range_negative(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"], "correct": -1}')
        self.assertIsNone(result)

    def test_parse_json_with_extra_fields(self):
        result = quiz.parse('{"question": "Тестовый вопрос", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0, "extra": "field"}')
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Тестовый вопрос")

    def test_parse_unicode_options(self):
        result = quiz.parse('{"question": "Тест", "options": ["Кириллица", "Ελληνικά", "中文"], "correct": 0}')
        self.assertIsNotNone(result)

    def test_generate_with_empty_topic(self):
        import asyncio
        from unittest import mock
        replies = iter([json.dumps({"question": "Какой моб самый опасный в Nether?", "options": ["a", "b", "c", "d"], "correct": 0}),
                        json.dumps({"question": "Какой блок нужен для портала в Нижний мир?", "options": ["e", "f", "g", "h"], "correct": 1})])

        async def fake(messages, **kw):
            return {"content": next(replies)}

        with mock.patch.object(quiz, "is_configured", return_value=True), mock.patch.object(quiz, "chat_with_fallback", fake):
            # Need 2 replies: one that fails parse, one that succeeds
            result = asyncio.run(quiz.generate(topic=""))
            self.assertIsNotNone(result)

    def test_record_answer_invalid_poll(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        result = quiz.record_answer("nonexistent", 5, "Тест", [0])
        self.assertIsNone(result)

    def test_record_answer_invalid_option(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        quiz.register_poll("p1", -1, 2)
        result = quiz.record_answer("p1", 5, "Тест", [99])
        self.assertIsNone(result)

    def test_leaderboard_empty(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        self.assertEqual(quiz.leaderboard(-1), [])

    def test_scoring_multiple_players(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        quiz.register_poll("p1", -1, 2)
        quiz.record_answer("p1", 5, "Саша", [0])
        quiz.record_answer("p1", 5, "Вова", [1])
        leaderboard = quiz.leaderboard(-1)
        self.assertEqual(len(leaderboard), 2)
        names = [name for name, _ in leaderboard]
        self.assertIn("Саша", names)
        self.assertIn("Вова", names)


if __name__ == "__main__":
    unittest.main()