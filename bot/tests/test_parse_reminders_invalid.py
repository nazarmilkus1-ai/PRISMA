import unittest
from bot.services.reminders import parse
from datetime import datetime

class TestParseRemindersInvalid(unittest.TestCase):
    def test_parse_invalid_format(self):
        # Проверяем, что parse("30m") возвращает None
        result = parse("30m", datetime.now())
        self.assertIsNone(result)

if __name__ == '__main__':
    unittest.main()
