from __future__ import annotations

import json
import unittest

from services import quiz


class QuizEdgeCaseTests(unittest.TestCase):
    def setUp(self):
        quiz._scores.clear()
        quiz._polls.clear()
        quiz._names.clear()

    def test_parse_empty_question(self):
        result = quiz.parse('{"question": "", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_question_too_short(self):
        result = quiz.parse('{"question": "Короткий", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_question_too_long(self):
        long_q = "?" * 301
        result = quiz.parse(f'{{"question": "{long_q}", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}}')
        self.assertIsNone(result)

    def test_parse_single_option(self):
        result = quiz.parse('{"question": "Тестовый вопрос?", "options": ["Один"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_special_chars_in_question(self):
        result = quiz.parse('{"question": "Тест <b>с</b> тегами & спецсимволами?", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0}')
        self.assertIsNotNone(result)

    def test_parse_duplicate_options(self):
        result = quiz.parse('{"question": "Тестовый вопрос?", "options": ["Один", "Два", "Один", "Четыре"], "correct": 0}')
        self.assertIsNone(result)

    def test_parse_correct_index_out_of_range(self):
        result = quiz.parse('{"question": "Тестовый вопрос?", "options": ["Один", "Два", "Три", "Четыре"], "correct": 4}')
        self.assertIsNone(result)

    def test_parse_correct_out_of_range_negative(self):
        result = quiz.parse('{"question": "Тест", "options": ["Один", "Два", "Три", "Четыре"], "correct": -1}')
        self.assertIsNone(result)

    def test_parse_json_with_extra_fields(self):
        result = quiz.parse('{"question": "Тестовый вопрос", "options": ["Один", "Два", "Три", "Четыре"], "correct": 0, "extra": "field"}')
        self.assertIsNotNone(result)
        self.assertEqual(result["question"], "Тестовый вопрос")

    def test_parse_unicode_options(self):
        result = quiz.parse('{"question": "Тестовый вопрос?", "options": ["Кириллица", "Ελληνικά", "中文", "English"], "correct": 0}')
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
        result = quiz.record_answer("nonexistent", 5, "Тест", [0])
        self.assertIsNone(result)

    def test_record_answer_invalid_option(self):
        quiz.register_poll("p1", -1, 2)
        result = quiz.record_answer("p1", 5, "Тест", [99])
        self.assertIsNone(result)

    def test_leaderboard_empty(self):
        self.assertEqual(quiz.leaderboard(-1), [])

    def test_scoring_multiple_players(self):
        quiz.register_poll("p1", -1, 0)
        quiz.record_answer("p1", 5, "Саша", [0])
        quiz.record_answer("p1", 5, "Вова", [1])
        leaderboard = quiz.leaderboard(-1)
        self.assertEqual(len(leaderboard), 2)
        names = [name for name, _ in leaderboard]
        self.assertIn("Саша", names)
        self.assertIn("Вова", names)


if __name__ == "__main__":
    unittest.main()