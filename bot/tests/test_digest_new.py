import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import digest


class DigestNewTests(unittest.TestCase):
    def test_template_basic(self):
        facts = {
            "online": "user1 · user2",
            "messages_today": 150,
            "top": [{"name": "Alice", "messages": 50}, {"name": "Bob", "messages": 30}],
            "events": [{"title": "Event1", "starts_at": "10:00"}],
        }
        result = digest.template(facts)
        self.assertIn("📰 Итоги дня в PRISMA", result)
        self.assertIn("💬 Сообщений в чате за сутки: 150", result)
        self.assertIn("🏆 Самые активные:", result)
        self.assertIn("Alice (50)", result)
        self.assertIn("Event1 — 10:00", result)

    def test_template_no_online(self):
        facts = {
            "messages_today": 10,
            "top": [],
            "events": [],
        }
        result = digest.template(facts)
        self.assertIn("📰 Итоги дня в PRISMA", result)
        self.assertIn("💬 Сообщений в чате за сутки: 10", result)
        self.assertNotIn("🏆 Самые активные:", result)
        self.assertNotIn("🎯 Ближайшие ивенты:", result)

    def test_has_news_true(self):
        facts = {"messages_today": 5}
        self.assertTrue(digest.has_news(facts))

    def test_has_news_false(self):
        facts = {}
        self.assertFalse(digest.has_news(facts))

    def test_enabled_global(self):
        self.assertTrue(digest.globally_enabled())

    def test_enabled_chat_off_global(self):
        import os
        original = os.getenv("AI_DIGEST")
        os.environ["AI_DIGEST"] = "0"
        try:
            self.assertFalse(digest.globally_enabled())
        finally:
            if original is None:
                os.environ.pop("AI_DIGEST", None)
            else:
                os.environ["AI_DIGEST"] = original

    def test_set_enabled(self):
        chat_id = 123
        digest.set_enabled(chat_id, True)
        self.assertTrue(digest.enabled(chat_id))
        digest.set_enabled(chat_id, False)
        self.assertFalse(digest.enabled(chat_id))

    def test_manual_allowed_initially(self):
        # Initially not allowed due to no manual call
        self.assertFalse(digest.manual_allowed(123))

    def test_manual_allowed_after_call(self):
        # First call should be allowed
        self.assertTrue(digest.manual_allowed(123))
        # Second call within cooldown should be disallowed
        self.assertFalse(digest.manual_allowed(123))

if __name__ == "__main__":
    unittest.main()
