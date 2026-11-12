import asyncio
import json
import os
import sys
import unittest
from unittest import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import digest, quiz  # noqa: E402
from services.ai import member_tools  # noqa: E402

GOOD = {"question": "Сколько блоков обсидиана нужно для портала в Нижний мир минимум?", "options": ["10", "12", "14", "4"],
        "correct": 0, "explanation": "Рамка 4x5 без углов: 10 блоков."}


class DigestTests(unittest.TestCase):
    FACTS = {"online": "Сервер: RUNNING · онлайн 3/20", "top": [{"name": "Саша", "messages": 40}, {"name": "Вова", "messages": 12}],
             "messages_today": 120, "events": [{"title": "Битва кланов", "starts_at": "2026-11-14 18:00"}]}

    def test_template_has_only_given_facts(self):
        text = digest.template(self.FACTS)
        for part in ("онлайн 3/20", "Саша (40)", "120", "Битва кланов"):
            self.assertIn(part, text)

    def test_quiet_day_is_not_posted(self):
        self.assertFalse(digest.has_news({"online": "x", "messages_today": 0}))
        self.assertTrue(digest.has_news(self.FACTS))

    def test_manual_cooldown(self):
        digest._last_manual.clear()
        self.assertTrue(digest.manual_allowed(-5, now=1000))
        self.assertFalse(digest.manual_allowed(-5, now=1100))
        self.assertTrue(digest.manual_allowed(-5, now=1000 + digest.COOLDOWN + 1))

    def test_build_uses_model_text_without_leaks_and_falls_back(self):
        async def ok(messages, **kw):
            self.assertIn("ФАКТЫ", messages[-1]["content"])
            return {"content": "I need to write. Final decision: x\n📰 Итоги дня в PRISMA\nСегодня 120 сообщений"}

        with mock.patch.object(digest, "is_configured", return_value=True), mock.patch.object(digest, "chat_with_fallback", ok):
            text = asyncio.run(digest.build(-5, self.FACTS))
        self.assertIn("120 сообщений", text)
        self.assertNotIn("I need", text)

        async def broken(messages, **kw):
            raise digest.AIError("down")

        with mock.patch.object(digest, "is_configured", return_value=True), mock.patch.object(digest, "chat_with_fallback", broken):
            self.assertIn("Битва кланов", asyncio.run(digest.build(-5, self.FACTS)))


class QuizTests(unittest.TestCase):
    def test_parse_validates(self):
        self.assertEqual(quiz.parse("вот: " + json.dumps(GOOD))["correct"], 0)
        bad = [dict(GOOD, correct=4), dict(GOOD, options=["a", "b", "c"]), dict(GOOD, options=["a", "a", "b", "c"]),
               dict(GOOD, question="?"), dict(GOOD, correct=True)]
        for item in bad:
            self.assertIsNone(quiz.parse(json.dumps(item)), item)
        self.assertIsNone(quiz.parse("не json"))

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
        self.assertIn("хватит", quiz.allowed(-9, now=100000 + 100 * (quiz.DAILY_CAP + 2)) or "")

    def test_generate_retries_then_returns_valid(self):
        replies = iter(["мусор", json.dumps(GOOD)])

        async def fake(messages, **kw):
            return {"content": next(replies)}

        with mock.patch.object(quiz, "is_configured", return_value=True), mock.patch.object(quiz, "chat_with_fallback", fake):
            self.assertEqual(asyncio.run(quiz.generate())["options"], GOOD["options"])


class PollToolTests(unittest.TestCase):
    def test_poll_tool_validates_and_limits(self):
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
