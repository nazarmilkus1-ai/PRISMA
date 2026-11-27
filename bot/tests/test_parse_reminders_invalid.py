import unittest
from services import reminders

class TestParseInvalid(unittest.TestCase):
    def test_invalid_relative_30m(self):
        self.assertIsNone(reminders.parse("30m"))
