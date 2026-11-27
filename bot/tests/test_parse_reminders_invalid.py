import unittest
from datetime import datetime
from services import reminders

NOW = datetime(2026, 11, 12, 10, 0, tzinfo=reminders.TZ)

class ParseInvalidTests(unittest.TestCase):
    def test_invalid_30m(self):
        self.assertIsNone(reminders.parse("30m", NOW))

if __name__ == "__main__":
    unittest.main()
