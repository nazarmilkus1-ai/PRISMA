import unittest
from services import reminders

NOW = reminders.TZ

class TestParseRemindersInvalid(unittest.TestCase):
    def test_invalid_30m(self):
        self.assertIsNone(reminders.parse("30m", NOW))

if __name__ == '__main__':
    unittest.main()
