import os
import sys
import unittest
from datetime import datetime, timedelta

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import reminders


class RemindersNewTests(unittest.TestCase):
    def test_parse_empty(self):
        self.assertIsNone(reminders.parse(""))
        self.assertIsNone(reminders.parse("   "))

    def test_parse_invalid_format(self):
        self.assertIsNone(reminders.parse("just a random string"))
        self.assertIsNone(reminders.parse("not json at all"))
        self.assertIsNone(reminders.parse("invalid format"))

    def test_parse_full_datetime(self):
        dt, text = reminders.parse("2026-12-01 18:00 текст")
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")

    def test_parse_relative_minutes(self):
        now = datetime.now()
        dt, text = reminders.parse(f"через 30 минут {now.strftime('%Y-%m-%d %H:%M')}", now)
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")
        # Should be +30 minutes from now
        self.assertEqual((dt - now).total_seconds(), 30 * 60)

    def test_parse_relative_hours(self):
        now = datetime.now()
        dt, text = reminders.parse(f"через 2 часа {now.strftime('%Y-%m-%d %H:%M')}", now)
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")
        self.assertEqual((dt - now).total_seconds(), 2 * 3600)

    def test_parse_clock_with_day(self):
        now = datetime.now()
        dt, text = reminders.parse(f"завтра 09:00 текст", now)
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")
        # Should be tomorrow at 09:00
        expected = now.replace(hour=9, minute=0, second=0, microsecond=0) + timedelta(days=1)
        self.assertEqual(dt.date(), expected.date())
        self.assertEqual(dt.hour, 9)

    def test_parse_clock_time_only(self):
        now = datetime.now()
        dt, text = reminders.parse(f"14:30 текст", now)
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")
        # Should be later today if time > now, else tomorrow
        if dt <= now:
            self.assertEqual(dt.date(), (now + timedelta(days=1)).date())

    def test_parse_invalid_unit(self):
        self.assertIsNone(reminders.parse("5 foo текст"))
        self.assertIsNone(reminders.parse("10 bar текст"))

    def test_parse_invalid_number(self):
        self.assertIsNone(reminders.parse("abc 5 минут"))
        self.assertIsNone(reminders.parse("10.5 часа"))

    def test_parse_past_time(self):
        # "вчера 10:00 текст" should parse to a past datetime
        dt, text = reminders.parse("вчера 10:00 текст")
        self.assertIsNotNone(dt)
        self.assertEqual(text, "текст")

if __name__ == "__main__":
    unittest.main()
