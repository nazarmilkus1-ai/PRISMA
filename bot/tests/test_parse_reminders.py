import os
import sys
import unittest
from datetime import datetime

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import reminders  # noqa: E402

NOW = datetime(2026, 11, 12, 10, 0, tzinfo=reminders.TZ)

class ParseTests(unittest.TestCase):
    def test_invalid_format(self):
        self.assertIsNone(reminders.parse("неправильный текст"))
        self.assertIsNone(reminders.parse("abc"))
        self.assertIsNone(reminders.parse("123"))
        self.assertIsNone(reminders.parse("несколько слов"))

    def test_invalid_date(self):
        self.assertIsNone(reminders.parse("2026-13-01 10:00 текст"))
        self.assertIsNone(reminders.parse("2026-12-01 25:00 текст"))
        self.assertIsNone(reminders.parse("2026-12-01 10:60 текст"))

    def test_invalid_time(self):
        self.assertIsNone(reminders.parse("2026-12-01 25:00 текст"))
        self.assertIsNone(reminders.parse("2026-12-01 10:60 текст"))
        self.assertIsNone(reminders.parse("2026-12-01 24:00:00 текст"))

    def test_invalid_minutes(self):
        self.assertIsNone(reminders.parse("2026-12-01 10:60 текст"))
        self.assertIsNone(reminders.parse("2026-12-01 24:00:00 текст"))

    def test_invalid_relative(self):
        self.assertIsNone(reminders.parse("30m"))  # неверный формат (нет текста)
        self.assertIsNone(reminders.parse("через 2 часа"))  # неверный формат (нет текста)
        self.assertIsNone(reminders.parse("5 лет текст"))  # неизвестная единица

if __name__ == '__main__':
    unittest.main()
