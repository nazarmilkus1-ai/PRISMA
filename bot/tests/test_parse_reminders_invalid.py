import unittest
from services import reminders

class TestParseRemindersInvalid(unittest.TestCase):
    def test_invalid_30m(self):
        self.assertIsNone(reminders.parse("30m"))

if __name__ == '__main__':
    unittest.main()
