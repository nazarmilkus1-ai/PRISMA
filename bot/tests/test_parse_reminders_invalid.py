import unittest
from datetime import datetime
from zoneinfo import ZoneInfo
from services.reminders import parse

class TestParseRemindersInvalid(unittest.TestCase):
    def setUp(self):
        self.base_time = datetime(2025, 6, 15, 12, 0, tzinfo=ZoneInfo("Europe/Kyiv"))

    def test_parse_invalid_30m(self):
        """'30m' should return None (unrecognized format)"""
        result = parse("30m", self.base_time)
        self.assertIsNone(result)
