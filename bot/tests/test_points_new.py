import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points


class PointsNewTests(unittest.TestCase):
    def test_positive_number(self):
        self.assertEqual(points.parse_amount("42"), 42)

    def test_negative_number(self):
        self.assertIsNone(points.parse_amount("-5"))

    def test_zero(self):
        self.assertEqual(points.parse_amount("0"), 0)

    def test_plus_sign(self):
        self.assertEqual(points.parse_amount("+10"), 10)

    def test_float_string(self):
        self.assertIsNone(points.parse_amount("3.14"))

    def test_text_string(self):
        self.assertIsNone(points.parse_amount("abc"))

    def test_empty_string(self):
        self.assertIsNone(points.parse_amount(""))

    def test_none_input(self):
        self.assertIsNone(points.parse_amount(None))

    def test_fmt_small_number(self):
        self.assertEqual(points.fmt(42), "42")

    def test_fmt_large_number(self):
        self.assertEqual(points.fmt(1234567), "1 234 567")

    def test_fmt_none(self):
        self.assertEqual(points.fmt(None), "0")

    def test_render_history_basic(self):
        text = points.render_history({"balance": 100, "items": []})
        self.assertIn("Баланс: 100 PP", text)

    def test_error_text_insufficient(self):
        self.assertIn("Не хватает", points.error_text("INSUFFICIENT_PP"))

    def test_error_text_unknown(self):
        self.assertIn("Не получилось", points.error_text("WAT"))


if __name__ == "__main__":
    unittest.main()