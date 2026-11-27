import os
import sys
import unittest
import json
import asyncio
import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import quiz
from services.ai import member_tools


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

class QuizScoringTests(unittest.TestCase):
    def test_scoring_one_answer_per_person(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        quiz.register_poll("p1", -1, 2)
        self.assertTrue(quiz.record_answer("p1", 5, "Саша", [2]))
        self.assertIsNone(quiz.record_answer("p1", 5, "Саша", [2]))  # second answer ignored
        self.assertFalse(quiz.record_answer("p1", 6, "Вова", [0]))
        self.assertIsNone(quiz.record_answer("unknown", 7, "Х", [0]))
        self.assertEqual(quiz.leaderboard(-1), [("Саша", 1)])

    def test_cooldown_and_daily_cap(self):
        quiz._last.clear(); quiz._day.clear()
        self.assertIsNone(quiz.allowed(-9, now=100000))
        self.assertIsNotNone(quiz.allowed(-9, now=100001))
        for i in range(quiz.DAILY_CAP):
            quiz._last.pop(-9, None)
            quiz.allowed(-9, now=100000 + 100 * (i + 1))
        quiz._last.pop(-9, None)
        result = quiz.allowed(-9, now=100000 + 100 * (quiz.DAILY_CAP + 2))
        self.assertIn("хватит", str(result) or "")

    def test_generate_retries_then_returns_valid(self):
        replies = iter(["мусор", '{"question": "Тест", "options": ["a", "b", "c", "d"], "correct": 0, "explanation": "x"}'])

        async def fake(messages, **kw):
            return {"content": next(replies)}

        with mock.patch.object(quiz, "is_configured", return_value=True), mock.patch.object(quiz, "chat_with_fallback", fake):
            self.assertEqual(asyncio.run(quiz.generate())["options"], ["a", "b", "c", "d"])

class QuizPollToolTests(unittest.TestCase):
    def test_poll_tool_validates_and_limits(self):
        from services.ai import member_tools
        member_tools._poll_times.clear()
        ctx = member_tools.Context(7, False, True, -1001)
        bad = asyncio.run(member_tools.execute("create_poll", {"question": "когда играем", "options": ["18"]}, ctx))
        self.assertIn("error", bad)
        for _ in range(3):
            ok = asyncio.run(member_tools.execute("create_poll", {"question": "Во сколько играем?", "options": ["18", "19", "19", "20"]}, ctx))
            self.assertIn("ok", ok)
        self.assertIn("error", asyncio.run(member_tools.execute("create_poll", {"question": "Ещё один опрос?", "options": ["да", "нет"]}, ctx)))
        text, payload = ctx.cards[0]
        self.assertEqual(text, member_tools.POLL_MARK)
        self.assertEqual(payload["options"], ["18", "19", "20"])  # duplicates dropped

    def test_poll_not_in_private(self):
        ctx = member_tools.Context(7, True, True)
        self.assertIn("error", asyncio.run(member_tools.execute("create_poll", {"question": "Опрос?", "options": ["а", "б"]}, ctx)))


if __name__ == "__main__":
    unittest.main()
