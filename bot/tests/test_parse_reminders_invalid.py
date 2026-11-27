import unittest
from bot.services.reminders import parse

class TestParseRemindersInvalid(unittest.TestCase):
    def test_invalid_format_30m(self):
        self.assertIsNone(parse("30m"))
