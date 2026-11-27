import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points


class PointsNewTests(unittest.TestCase):
    def test_parse_amount_basic(self):
        self.assertEqual(points.parse_amount("50"), 50)
        self.assertEqual(points.parse_amount("+100"), 100)
        self.assertEqual(points.parse_amount("-7"), -7)

    def test_parse_amount_invalid(self):
        self.assertIsNone(points.parse_amount("abc"))
        self.assertIsNone(points.parse_amount("1.5"))
        self.assertIsNone(points.parse_amount(""))
        self.assertIsNone(points.parse_amount("   "))
        self.assertIsNone(points.parse_amount(None))
        self.assertIsNone(points.parse_amount("-3.14"))
        self.assertIsNone(points.parse_amount("-"))
        self.assertIsNone(points.parse_amount("True"))
        self.assertIsNone(points.parse_amount("+"))
        self.assertIsNone(points.parse_amount("５０"))

    def test_parse_amount_edge(self):
        self.assertEqual(points.parse_amount("  50  "), 50)
        self.assertEqual(points.parse_amount("0"), 0)
        self.assertEqual(points.parse_amount("+0"), 0)

if __name__ == "__main__":
    unittest.main()
