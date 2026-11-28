import pytest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from bot.services.reminders import parse, TZ

class TestParseRemindersInvalid:
    def setup_method(self):
        self.now = datetime(2025, 6, 15, 12, 0, tzinfo=TZ)  # reference time

    def test_invalid_minutes_format(self):
        # '30m' is not a recognized format, should return None
        assert parse('30m', now=self.now) is None
