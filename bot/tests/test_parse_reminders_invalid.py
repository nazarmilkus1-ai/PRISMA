import unittest
from services.reminders import parse

class TestParseRemindersInvalid(unittest.TestCase):
    def test_invalid_input(self):
        self.assertIsNone(parse('30m'))
