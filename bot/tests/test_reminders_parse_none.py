import unittest
from bot.services.reminders import parse
from bot.tests.test_reminders import NOW

class TestParseNone(unittest.TestCase):
    def test_unrecognized_time(self):
        when, _ = parse("18:30 ивент", NOW)
        self.assertIsNone(when)