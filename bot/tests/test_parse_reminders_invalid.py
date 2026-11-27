import unittest
from services import reminders

NOW = reminders.TZ

class TestParseRemindersInvalid(unittest.TestCase):
    def test_invalid_format_30m(self):
        result = reminders.parse("30m", NOW)
        self.assertIsNone(result)

if __name__ == "__main__":
    unittest.main(verbosity=2)
