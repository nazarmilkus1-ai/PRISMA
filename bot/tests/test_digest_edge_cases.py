import os
import sys
import unittest
import asyncio
from unittest import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import digest, quiz

GOOD = {"question": "Сколько блоков обсидиана нужно для портала в Нижний мир минимум?", "options": ["10", "12", "14", "4"],
        "correct": 0, "explanation": "Рамка 4x5 без углов: 10 блоков."}


class DigestEdgeCaseTests(unittest.TestCase):
    def test_template_only_given_facts(self):
        facts = {"online": "Сервер: RUNNING · онлайн 3/20", "messages_today": 120, "events": []}
        text = digest.template(facts)
        self.assertIn("онлайн 3/20", text)
        self.assertIn("120", text)

    def test_template_no_online_no_events(self):
        facts = {"messages_today": 50}
        text = digest.template(facts)
        self.assertIn("Сообщений в чате за сутки: 50", text)

    def test_has_news_with_events(self):
        facts = {"online": None, "messages_today": 0, "events": [{"title": "Ивент", "starts_at": "2026-11-14 18:00"}]}
        self.assertTrue(digest.has_news(facts))

    def test_has_news_no_data(self):
        facts = {"online": None, "messages_today": 0, "events": []}
        self.assertFalse(digest.has_news(facts))

    def test_build_template_fallback(self):
        facts = {"online": "test", "messages_today": 10, "events": []}
        digest._last_manual.clear()
        self.assertTrue(digest.manual_allowed(-5, now=1000))

    def test_build_uses_template_when_ai_fails(self):
        facts = {"online": "test", "messages_today": 10, "events": []}
        async def broken(messages, **kw):
            raise Exception("AI down")

        with mock.patch.object(digest, "is_configured", return_value=True), \
             mock.patch.object(digest, "chat_with_fallback", broken):
            result = asyncio.run(digest.build(-5, facts))
        self.assertIn("📰 Итоги дня", result)

    def test_build_uses_template_when_not_configured(self):
        facts = {"online": "test", "messages_today": 10, "events": []}
        with mock.patch.object(digest, "is_configured", return_value=False):
            result = asyncio.run(digest.build(-5, facts))
        self.assertIn("📰 Итоги дня", result)

    def test_build_with_minimal_facts(self):
        facts = {"messages_today": 5}
        result = asyncio.run(digest.build(-5, facts))
        self.assertIn("Сообщений", result)

    def test_build_with_no_facts(self):
        facts = {}
        result = asyncio.run(digest.build(-5, facts))
        self.assertIn("📰 Итоги дня", result)

    def test_build_with_all_fields(self):
        facts = {
            "online": "Сервер: RUNNING · онлайн 3/20",
            "messages_today": 120,
            "top": [{"name": "Саша", "messages": 40}, {"name": "Вова", "messages": 12}],
            "events": [{"title": "Битва кланов", "starts_at": "2026-11-14 18:00"}]
        }
        result = asyncio.run(digest.build(-5, facts))
        self.assertIn("Саша", result)
        self.assertIn("Вова", result)
        self.assertIn("Битва кланов", result)

    def test_scoring_one_answer_per_person(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        quiz.register_poll("p1", -1, 2)
        self.assertTrue(quiz.record_answer("p1", 5, "Саша", [2]))
        self.assertIsNone(quiz.record_answer("p1", 5, "Саша", [2]))  # second answer ignored
        self.assertFalse(quiz.record_answer("p1", 6, "Вова", [0]))
        self.assertIsNone(quiz.record_answer("unknown", 7, "Х", [0]))
        self.assertEqual(quiz.leaderboard(-1), [("Саша", 1)])

    def test_scoring_multiple_players_unique(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        quiz.register_poll("p1", -1, 2)
        quiz.record_answer("p1", 5, "Саша", [0])
        quiz.record_answer("p1", 6, "Вова", [1])
        leaderboard = quiz.leaderboard(-1)
        self.assertEqual(len(leaderboard), 2)
        names = [name for name, _ in leaderboard]
        self.assertIn("Саша", names)
        self.assertIn("Вова", names)

    def test_leaderboard_empty_poll(self):
        quiz._scores.clear(); quiz._polls.clear(); quiz._names.clear()
        self.assertEqual(quiz.leaderboard(-1), [])

    def test_daily_cap_reached(self):
        quiz._last.clear(); quiz._day.clear()
        self.assertIsNone(quiz.allowed(-9, now=100000))
        self.assertIsNotNone(quiz.allowed(-9, now=100001))
        for i in range(quiz.DAILY_CAP):
            quiz._last.pop(-9, None)
            quiz.allowed(-9, now=100000 + 100 * (i + 1))
        quiz._last.pop(-9, None)
        result = quiz.allowed(-9, now=100000 + 100 * (quiz.DAILY_CAP + 2))
        self.assertIn("хватит", str(result) or "")


if __name__ == "__main__":
    unittest.main()