import pytest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from bot.services.reminders import parse, TZ


class TestRemindersParse:
    """Тесты для функции parse напоминаний."""

    def setup_method(self):
        self.now = datetime(2025, 6, 15, 12, 0, tzinfo=TZ)  # воскресенье

    # --- Полная дата (YYYY-MM-DD HH:MM текст) ---
    def test_full_date_valid(self):
        result = parse("2025-12-01 18:30 встреча", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 12, 1, 18, 30, tzinfo=TZ)
        assert text == "встреча"

    def test_full_date_invalid_day(self):
        # 31 февраля не существует
        assert parse("2025-02-31 10:00 текст", now=self.now) is None

    def test_full_date_invalid_hour(self):
        assert parse("2025-12-01 25:00 текст", now=self.now) is None

    def test_full_date_invalid_minute(self):
        assert parse("2025-12-01 10:60 текст", now=self.now) is None

    def test_full_date_no_text(self):
        # нет текста после времени
        assert parse("2025-12-01 18:30", now=self.now) is None

    # --- Часы с указанием дня (сегодня/завтра/послезавтра HH:MM текст) ---
    def test_clock_today(self):
        result = parse("сегодня 14:30 обед", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 15, 14, 30, tzinfo=TZ)
        assert text == "обед"

    def test_clock_tomorrow(self):
        result = parse("завтра 09:00 звонок", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 16, 9, 0, tzinfo=TZ)
        assert text == "звонок"

    def test_clock_day_after_tomorrow(self):
        result = parse("послезавтра 10:00 встреча", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 17, 10, 0, tzinfo=TZ)
        assert text == "встреча"

    def test_clock_today_with_v_prefix(self):
        result = parse("в 15:00 текст", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 15, 15, 0, tzinfo=TZ)
        assert text == "текст"

    def test_clock_today_with_at_prefix(self):
        result = parse("at 16:00 текст", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 15, 16, 0, tzinfo=TZ)
        assert text == "текст"

    def test_clock_past_time_moves_to_tomorrow(self):
        # сейчас 12:00, просим 10:00 без указания дня -> должно стать завтра
        result = parse("10:00 ранний подъём", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 16, 10, 0, tzinfo=TZ)
        assert text == "ранний подъём"

    def test_clock_future_time_stays_today(self):
        # сейчас 12:00, просим 14:00 без указания дня -> остаётся сегодня
        result = parse("14:00 обед", now=self.now)
        assert result is not None
        when, text = result
        assert when == datetime(2025, 6, 15, 14, 0, tzinfo=TZ)
        assert text == "обед"

    def test_clock_invalid_hour(self):
        assert parse("25:00 текст", now=self.now) is None

    def test_clock_invalid_minute(self):
        assert parse("12:60 текст", now=self.now) is None

    def test_clock_no_text(self):
        assert parse("14:30", now=self.now) is None

    # --- Относительное время (N единиц текст) ---
    def test_relative_minutes_ru(self):
        result = parse("30м перерыв", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=30)
        assert when == expected
        assert text == "перерыв"

    def test_relative_minutes_ru_variants(self):
        for unit in ["мин", "минут", "минуты", "минуту"]:
            result = parse(f"15 {unit} текст", now=self.now)
            assert result is not None, f"failed for {unit}"
            when, text = result
            expected = self.now + timedelta(minutes=15)
            assert when == expected
            assert text == "текст"

    def test_relative_hours_ru(self):
        result = parse("2 часа отдых", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(hours=2)
        assert when == expected
        assert text == "отдых"

    def test_relative_hours_ru_variants(self):
        for unit in ["ч", "час", "часа", "часов"]:
            result = parse(f"1 {unit} текст", now=self.now)
            assert result is not None, f"failed for {unit}"
            when, text = result
            expected = self.now + timedelta(hours=1)
            assert when == expected
            assert text == "текст"

    def test_relative_days_ru(self):
        result = parse("3 дня дедлайн", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(days=3)
        assert when == expected
        assert text == "дедлайн"

    def test_relative_days_ru_variants(self):
        for unit in ["д", "дн", "день", "дня", "дней"]:
            result = parse(f"1 {unit} текст", now=self.now)
            assert result is not None, f"failed for {unit}"
            when, text = result
            expected = self.now + timedelta(days=1)
            assert when == expected
            assert text == "текст"

    def test_relative_minutes_en(self):
        result = parse("30 min текст", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=30)
        assert when == expected
        assert text == "текст"

    def test_relative_hours_en(self):
        result = parse("2 h текст", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(hours=2)
        assert when == expected
        assert text == "текст"

    def test_relative_days_en(self):
        result = parse("1 d текст", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(days=1)
        assert when == expected
        assert text == "текст"

    def test_relative_with_cherez_prefix(self):
        result = parse("через 30 мин текст", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(minutes=30)
        assert when == expected
        assert text == "текст"

    def test_relative_with_in_prefix(self):
        result = parse("in 2 hours текст", now=self.now)
        assert result is not None
        when, text = result
        expected = self.now + timedelta(hours=2)
        assert when == expected
        assert text == "текст"

    def test_relative_no_text(self):
        # нет текста после времени
        assert parse("30 мин", now=self.now) is None

    def test_relative_invalid_unit(self):
        assert parse("30 секунд текст", now=self.now) is None

    def test_relative_zero_minutes(self):
        assert parse("0 мин текст", now=self.now) is None

    # --- Невалидные форматы ---
    def test_invalid_format_30m(self):
        assert parse("30m") is None

    def test_empty_string(self):
        assert parse("") is None

    def test_only_whitespace(self):
        assert parse("   ") is None

    def test_random_text(self):
        assert parse("привет как дела") is None

    def test_none_input(self):
        assert parse(None) is None
