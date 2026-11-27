import unittest
from services import reminders

NOW = reminders.TZ
def test_invalid_30m():
    self.assertIsNone(reminders.parse("30m", NOW))

if __name__ == '__main__':
    unittest.main()
