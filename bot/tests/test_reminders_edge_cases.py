import os
import sys
import unittest
from datetime import datetime

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import reminders

NOW = datetime(2026, 11, 12, 10, 0, tzinfo=reminders.TZ)


class RemindersEdgeCaseTests(unittest.TestCase):
    def test_parse_empty_string(self):
        self.assertIsNone(reminders.parse("", NOW))

    def test_parse_just_text(self):
        self.assertIsNone(reminders.parse("просто текст", NOW))

    def test_parse_negative_minutes(self):
        self.assertIsNone(reminders.parse("-5m текст", NOW))

    def test_parse_float_minutes(self):
        self.assertIsNone(reminders.parse("5.5m текст", NOW))

    def test_parse_no_number_unit_only(self):
        self.assertIsNone(reminders.parse("м текст", NOW))

    def test_parse_very_large_minutes(self):
        result = reminders.parse("999999m текст", NOW)
        self.assertIsNotNone(result)

    def test_parse_через_large_number(self):
        when, text = reminders.parse("через 1000 минут напоминание", NOW)
        self.assertIsNotNone(result)
        self.assertEqual(text, "напоминание")

    def test_parse_25_99_garbage(self):
        self.assertIsNone(reminders.parse("25:99 текст", NOW))

    def test_parse_5_years(self):
        self.assertIsNone(reminders.parse("5 лет текст", NOW))

    def test_parse_just_unit_no_number(self):
        self.assertIsNone(reminders.parse("минут", NOW))

    def test_friendly_error_reminder_limit(self):
        self.assertIn("20", reminders.friendly_error("REMINDER_LIMIT"))

    def test_friendly_error_reminder_time_too_far(self):
        self.assertIn("год", reminders.friendly_error("REMINDER_TIME_TOO_FAR"))

    def test_friendly_error_reminder_text_invalid(self):
        result = reminders.friendly_error("REMINDER_TEXT_INVALID")
        self.assertIn("300", result)
        self.assertIn("Бесплатно", result)

    def test_friendly_error_unknown(self):
        self.assertIn("Не получилось", reminders.friendly_error("UNKNOWN_ERROR"))

    def test_fmt_with_datetime(self):
        from datetime import datetime
        when = datetime(2026, 12, 25, 14, 30, tzinfo=reminders.TZ)
        result = reminders.fmt(when)
        self.assertIn("25.12", result)
        self.assertIn("14:30", result)

    def test_fmt_with_string(self):
        result = reminders.fmt("2026-12-25T14:30:00+00:00")
        self.assertIn("25.12", result)
        self.assertIn("16:30", result)

    def test_fmt_with_none(self):
        result = reminders.fmt(None)
        self.assertEqual(result, "00.00")

    def test_fmt_with_past_date(self):
        from datetime import datetime
        when = datetime(2020, 1, 1, 0, 0, tzinfo=reminders.TZ)
        result = reminders.fmt(when)
        self.assertIn("01.01", result)
        self.assertIn("00:00", result)

    def test_fmt_with_empty_string(self):
        result = reminders.fmt("")
        self.assertEqual(result, "00.00")

    def test_fmt_with_future_date(self):
        from datetime import datetime
        when = datetime(2030, 6, 15, 20, 45, tzinfo=reminders.TZ)
        result = reminders.fmt(when)
        self.assertIn("15.06", result)
        self.assertIn("20:45", result)


if __name__ == "__main__":
    unittest.main()