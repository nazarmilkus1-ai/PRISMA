import pytest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from bot.services.reminders import parse, TZ


class TestParseReminders:
    """Тесты для функции parse напоминаний."""

    def setup_method(self):
        self.now = datetime(2025, 6, 15, 12, 0, tzinfo=TZ)

    # Относительное время: "через 30 мин текст", "30м текст", "2 часа текст"
    def test_relative_minutes_cyrillic(self):
        result = parse("через 30 мин купить хлеб", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=30)
        assert when == expected
        assert text == "купить хлеб"

    def test_relative_minutes_short_cyrillic(self):
        result = parse("30м позвонить маме", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=30)
        assert when == expected
        assert text == "позвонить маме"

    def test_relative_minutes_english(self):
        result = parse("in 45 min check email", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=45)
        assert when == expected
        assert text == "check email"

    def test_relative_hours_cyrillic(self):
        result = parse("через 2 часа совещание", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(hours=2)
        assert when == expected
        assert text == "совещание"

    def test_relative_hours_short(self):
        result = parse("3ч отдых", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(hours=3)
        assert when == expected
        assert text == "отдых"

    def test_relative_days_cyrillic(self):
        result = parse("через 1 день дедлайн", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(days=1)
        assert when == expected
        assert text == "дедлайн"

    def test_relative_days_short(self):
        result = parse("2д поездка", self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(days=2)
        assert when == expected
        assert text == "поездка"

    # Точное время сегодня: "14:30 текст"
    def test_clock_today_future(self):
        result = parse("14:30 обед", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 15, 14, 30, tzinfo=TZ)
        assert when == expected
        assert text == "обед"

    def test_clock_today_past_rolls_to_tomorrow(self):
        # 10:00 уже прошло, должно стать завтра
        result = parse("10:00 завтрак", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 16, 10, 0, tzinfo=TZ)
        assert when == expected
        assert text == "завтрак"

    def test_clock_with_at_english(self):
        result = parse("at 18:00 meeting", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 15, 18, 0, tzinfo=TZ)
        assert when == expected
        assert text == "meeting"

    def test_clock_with_dot_separator(self):
        result = parse("15.30 кофе", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 15, 15, 30, tzinfo=TZ)
        assert when == expected
        assert text == "кофе"

    # С указанием дня: "завтра 09:00 текст", "послезавтра 10:00 текст"
    def test_clock_tomorrow(self):
        result = parse("завтра 09:00 пробежка", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 16, 9, 0, tzinfo=TZ)
        assert when == expected
        assert text == "пробежка"

    def test_clock_day_after_tomorrow(self):
        result = parse("послезавтра 10:00 встреча", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 17, 10, 0, tzinfo=TZ)
        assert when == expected
        assert text == "встреча"

    def test_clock_today_explicit(self):
        result = parse("сегодня 18:00 ужин", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 6, 15, 18, 0, tzinfo=TZ)
        assert when == expected
        assert text == "ужин"

    # Полная дата: "2026-12-01 18:00 текст"
    def test_full_date(self):
        result = parse("2026-12-01 18:00 новый год", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2026, 12, 1, 18, 0, tzinfo=TZ)
        assert when == expected
        assert text == "новый год"

    def test_full_date_with_dot(self):
        result = parse("2025-07-20 12.30 летний лагерь", self.now)
        assert result is not None
        when, text = result
        expected = datetime(2025, 7, 20, 12, 30, tzinfo=TZ)
        assert when == expected
        assert text == "летний лагерь"

    # Невалидные случаи
    def test_invalid_format_30m_no_text(self):
        # нет текста после времени
        assert parse("30m") is None
        assert parse("30 мин") is None
        assert parse("через 1 час") is None

    def test_invalid_time_values(self):
        # неверные часы/минуты
        assert parse("25:00 спать") is None
        assert parse("12:60 обед") is None
        assert parse("99:99 ошибка") is None

    def test_invalid_date_values(self):
        # неверная дата
        assert parse("2025-13-01 12:00 ошибка") is None
        assert parse("2025-02-30 12:00 ошибка") is None

    def test_invalid_relative_unit(self):
        # неизвестная единица измерения
        assert parse("через 5 недель отдых") is None
        assert parse("10 секунд быстро") is None

    def test_empty_or_whitespace(self):
        assert parse("") is None
        assert parse("   ") is None
        assert parse(None) is None  # type: ignore

    def test_text_too_short_after_relative(self):
        # пробел есть, но текста нет
        assert parse("через 10 мин ") is None
        assert parse("10м ") is None
