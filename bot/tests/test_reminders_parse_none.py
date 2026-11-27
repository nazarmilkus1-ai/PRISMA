import unittest
from services import reminders

NOW = reminders.now_local()

class ParseTests(unittest.TestCase):
    def test_parse_unrecognized_input_returns_none(self):
        # Проверяем, что parse возвращает None для нераспознанного ввода
        result = reminders.parse("18:30 ивент", NOW)
        self.assertIsNone(result)

if __name__ == '__main__':
    unittest.main()
