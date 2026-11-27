import unittest
from datetime import datetime
from services import reminders

NOW = datetime(2026, 11, 12, 10, 0, tzinfo=reminders.TZ)

class ParseInvalidTests(unittest.TestCase):
    def test_unrecognized_time_string(self):
        result = reminders.parse("09:00 рынок", NOW)
        self.assertIsNone(result)

    def test_unrecognized_relative(self):
        result = reminders.parse("5 unknown", NOW)
        self.assertIsNone(result)

    def test_invalid_date(self):
        result = reminders.parse("2026-13-01 10:00 текст", NOW)
        self.assertIsNone(result)

    def test_invalid_time(self):
        result = reminders.parse("25:99 текст", NOW)
        self.assertIsNone(result)

    def test_invalid_full_date(self):
        result = reminders.parse("2026-02-30 10:00", NOW)
        self.assertIsNone(result)

    def test_empty_string(self):
        result = reminders.parse("", NOW)
        self.assertIsNone(result)

    def test_none_input(self):
        result = reminders.parse(None, NOW)
        self.assertIsNone(result)

if __name__ == "__main__":
    unittest.main(verbosity=2)
