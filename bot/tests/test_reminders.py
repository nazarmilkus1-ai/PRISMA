import os
import sys
import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
os.environ.setdefault("REMINDER_TZ", "Europe/Kyiv")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.reminders import parse, fmt, now_local  # noqa: E402


class TestParseReminders(unittest.TestCase):
    """Тесты для функции parse напоминаний."""

    def setUp(self):
        self.base_time = datetime(2025, 6, 15, 12, 0, tzinfo=ZoneInfo("Europe/Kyiv"))

    def test_parse_relative_minutes_cyrillic(self):
        """30м текст -> через 30 минут."""
        result = parse("30м купить хлеб", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(minute=30)  # 12:00 + 30 мин = 12:30
        self.assertEqual(when, expected)
        self.assertEqual(text, "купить хлеб")

    def test_parse_relative_minutes_latin(self):
        """30m text -> через 30 минут."""
        result = parse("30m buy bread", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(minute=30)
        self.assertEqual(when, expected)
        self.assertEqual(text, "buy bread")

    def test_parse_relative_hours_cyrillic(self):
        """2ч текст -> через 2 часа."""
        result = parse("2ч позвонить маме", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(hour=14)  # 12:00 + 2 часа = 14:00
        self.assertEqual(when, expected)
        self.assertEqual(text, "позвонить маме")

    def test_parse_relative_hours_latin(self):
        """2h text -> через 2 часа."""
        result = parse("2h call mom", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(hour=14)
        self.assertEqual(when, expected)
        self.assertEqual(text, "call mom")

    def test_parse_relative_days_cyrillic(self):
        """1д текст -> через 1 день."""
        result = parse("1д сходить в магазин", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 16, 12, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "сходить в магазин")

    def test_parse_relative_with_prefix_through(self):
        """через 30м текст -> через 30 минут."""
        result = parse("через 30м купить хлеб", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(minute=42)
        self.assertEqual(when, expected)
        self.assertEqual(text, "купить хлеб")

    def test_parse_relative_with_prefix_in(self):
        """in 30m text -> через 30 минут."""
        result = parse("in 30m buy bread", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(minute=42)
        self.assertEqual(when, expected)
        self.assertEqual(text, "buy bread")

    def test_parse_clock_time_today(self):
        """14:30 текст -> сегодня в 14:30."""
        result = parse("14:30 встреча", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 15, 14, 30, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "встреча")

    def test_parse_clock_time_with_at(self):
        """в 14:30 текст -> сегодня в 14:30."""
        result = parse("в 14:30 встреча", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 15, 14, 30, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "встреча")

    def test_parse_clock_time_tomorrow(self):
        """завтра 09:00 текст -> завтра в 09:00."""
        result = parse("завтра 09:00 завтрак", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 16, 9, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "завтрак")

    def test_parse_clock_time_day_after_tomorrow(self):
        """послезавтра 10:00 текст -> послезавтра в 10:00."""
        result = parse("послезавтра 10:00 обед", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 17, 10, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "обед")

    def test_parse_clock_time_past_moves_to_tomorrow(self):
        """10:00 текст (время уже прошло) -> завтра в 10:00."""
        # base_time = 12:00, 10:00 уже прошло
        result = parse("10:00 ранний подъём", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 16, 10, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "ранний подъём")

    def test_parse_full_date(self):
        """2026-12-01 18:00 текст -> точная дата."""
        result = parse("2026-12-01 18:00 новый год", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2026, 12, 1, 18, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "новый год")

    def test_parse_full_date_with_dot_separator(self):
        """2026-12-01 18.00 текст -> точка как разделитель."""
        result = parse("2026-12-01 18.00 новый год", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2026, 12, 1, 18, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "новый год")

    def test_parse_invalid_no_text_after_time(self):
        """30м без текста -> None."""
        result = parse("30м", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_unknown_unit(self):
        """30x текст -> None (неизвестная единица)."""
        result = parse("30x текст", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_empty_string(self):
        """Пустая строка -> None."""
        result = parse("", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_only_whitespace(self):
        """Только пробелы -> None."""
        result = parse("   ", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_none(self):
        """None -> None."""
        result = parse(None, self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_clock_time_wrong_format(self):
        """25:00 текст -> None (неверный час)."""
        result = parse("25:00 текст", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_clock_time_wrong_minute(self):
        """12:60 текст -> None (неверная минута)."""
        result = parse("12:60 текст", self.base_time)
        self.assertIsNone(result)

    def test_parse_invalid_full_date_wrong(self):
        """2026-13-01 18:00 текст -> None (неверный месяц)."""
        result = parse("2026-13-01 18:00 текст", self.base_time)
        self.assertIsNone(result)

    def test_parse_case_insensitive(self):
        """Регистр не важен: 30М, 2Ч, ЗАВТРА."""
        result = parse("30М ТЕКСТ", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = self.base_time.replace(minute=30)
        self.assertEqual(when, expected)
        self.assertEqual(text, "ТЕКСТ")

        result = parse("ЗАВТРА 09:00 ТЕКСТ", self.base_time)
        self.assertIsNotNone(result)
        when, text = result
        expected = datetime(2025, 6, 16, 9, 0, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(when, expected)
        self.assertEqual(text, "ТЕКСТ")


class TestFmtReminders(unittest.TestCase):
    """Тесты для функции fmt форматирования времени."""

    def test_fmt_none(self):
        """None -> 00.00."""
        self.assertEqual(fmt(None), "00.00")

    def test_fmt_empty_string(self):
        """Пустая строка -> 00.00."""
        self.assertEqual(fmt(""), "00.00")

    def test_fmt_whitespace_string(self):
        """Пробелы -> 00.00."""
        self.assertEqual(fmt("   "), "00.00")

    def test_fmt_datetime_with_tz(self):
        """datetime с таймзоной -> формат дд.мм чч:мм."""
        dt = datetime(2025, 12, 1, 18, 30, tzinfo=ZoneInfo("Europe/Kyiv"))
        self.assertEqual(fmt(dt), "01.12 18:30")

    def test_fmt_datetime_without_tz(self):
        """datetime без таймзоны -> как есть."""
        dt = datetime(2025, 12, 1, 18, 30)
        self.assertEqual(fmt(dt), "01.12 18:30")

    def test_fmt_iso_string_with_z(self):
        """ISO строка с Z (UTC) -> конвертируется в локальное время (Киев)."""
        # 2025-12-01 в Киеве UTC+2 (зима), 18:30 UTC = 20:30 Киев
        self.assertEqual(fmt("2025-12-01T18:30:00Z"), "01.12 20:30")

    def test_fmt_iso_string_with_offset(self):
        """ISO строка с offset +03:00 -> конвертируется в локальное время (Киев)."""
        # 2025-12-01 в Киеве UTC+2 (зима), 18:30+03:00 = 17:30 Киев
        self.assertEqual(fmt("2025-12-01T18:30:00+03:00"), "01.12 17:30")


class TestNowLocal(unittest.TestCase):
    """Тесты для функции now_local."""

    def test_now_local_returns_datetime_with_tz(self):
        """now_local возвращает datetime с таймзоной Europe/Kyiv."""
        now = now_local()
        self.assertIsInstance(now, datetime)
        self.assertIsNotNone(now.tzinfo)
        self.assertEqual(str(now.tzinfo), "Europe/Kyiv")


if __name__ == "__main__":
    unittest.main()
