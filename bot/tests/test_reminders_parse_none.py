import unittest
from services import reminders

NOW = reminders.TZ.utcnow()

class TestParseNone(unittest.TestCase):
    def test_unrecognized_time_string(self):
        result = reminders.parse("18:30 ивент", NOW)
        self.assertIsNone(result)

if __name__ == "__main__":
    unittest.main(verbosity=2)
