import os
import sys
import unittest
from datetime import datetime

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import reminders  # noqa: E402
from services.ai import admin_tools, member_tools  # noqa: E402

NOW = datetime(2026, 11, 12, 10, 0, tzinfo=reminders.TZ)


class ParseTests(unittest.TestCase):
    def test_relative(self):
        when, text = reminders.parse("30м позвонить", NOW)
        self.assertEqual((when - NOW).total_seconds(), 1800)
        self.assertEqual(text, "позвонить")
        when, text = reminders.parse("через 2 часа проверить заявки", NOW)
        self.assertEqual((when - NOW).total_seconds(), 7200)
        self.assertEqual(text, "проверить заявки")
        self.assertEqual((reminders.parse("1д ивент", NOW)[0] - NOW).days, 1)

    def test_clock_today_or_tomorrow(self):
        when, _ = reminders.parse("18:30 ивент", NOW)
        self.assertEqual((when.day, when.hour, when.minute), (12, 18, 30))
        when, _ = reminders.parse("09:00 рынок", NOW)  # already passed today
        self.assertEqual(when.day, 13)
        when, text = reminders.parse("завтра 09:00 рынок", NOW)
        self.assertEqual((when.day, text), (13, "рынок"))

    def test_full_date_and_garbage(self):
        when, text = reminders.parse("2026-12-01 18:00 сезон", NOW)
        self.assertEqual((when.month, when.day, when.hour, text), (12, 1, 18, "сезон"))
        self.assertIsNone(reminders.parse("когда-нибудь потом", NOW))
        self.assertIsNone(reminders.parse("25:99 текст", NOW))
        self.assertIsNone(reminders.parse("5 лет текст", NOW))

    def test_friendly_errors(self):
        self.assertIn("20", reminders.friendly_error("REMINDER_LIMIT"))
        self.assertIn("год", reminders.friendly_error("... REMINDER_TIME_TOO_FAR ..."))


class ToolWiringTests(unittest.TestCase):
    def test_both_assistants_have_reminder_tools(self):
        for tools in (member_tools.TOOLS, admin_tools.TOOLS):
            names = {t["function"]["name"] for t in tools}
            self.assertTrue({"set_reminder", "list_reminders", "cancel_reminder"} <= names)


class ToolBehaviourTests(unittest.IsolatedAsyncioTestCase):
    async def test_rejects_missing_time(self):
        result = await member_tools.reminders_tool("set_reminder", {"text": "x"}, 1)
        self.assertIn("error", result)


if __name__ == "__main__":
    unittest.main()
