import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points


class PointsAmountParseTests(unittest.TestCase):
    def test_parse_positive_integer(self):
        self.assertEqual(points.parse_amount("42"), 42)
        self.assertEqual(points.parse_amount("+42"), 42)

    def test_parse_negative_integer(self):
        self.assertEqual(points.parse_amount("-5"), -5)

    def test_parse_zero(self):
        self.assertEqual(points.parse_amount("0"), 0)

    def test_parse_with_spaces(self):
        self.assertEqual(points.parse_amount("  7  "), 7)

    def test_parse_float_rejected(self):
        self.assertIsNone(points.parse_amount("3.14"))
        self.assertIsNone(points.parse_amount("-2.5"))

    def test_parse_non_digits_rejected(self):
        self.assertIsNone(points.parse_amount("abc"))
        self.assertIsNone(points.parse_amount("-"))
        self.assertIsNone(points.parse_amount("+"))
        self.assertIsNone(points.parse_amount("True"))
        self.assertIsNone(points.parse_amount("５０"))  # Unicode digits

    def test_parse_none(self):
        self.assertIsNone(points.parse_amount(None))

    def test_parse_empty_string(self):
        self.assertIsNone(points.parse_amount(""))

class PointsFmtTests(unittest.TestCase):
    def test_fmt_positive(self):
        self.assertEqual(points.fmt(1234567), "1 234 567")
        self.assertEqual(points.fmt(100), "100")
        self.assertEqual(points.fmt(5), "5")

    def test_fmt_zero_and_negative(self):
        self.assertEqual(points.fmt(0), "0")
        self.assertEqual(points.fmt(-1234567), "-1 234 567")
        self.assertEqual(points.fmt(-5), "-5")

    def test_fmt_none(self):
        self.assertEqual(points.fmt(None), "0")

    def test_fmt_large_numbers(self):
        self.assertEqual(points.fmt(999999999), "999 999 999")
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")

class PointsErrorTextTests(unittest.TestCase):
    def test_error_codes_exist(self):
        self.assertIn("Не хватает", points.error_text("INSUFFICIENT_PP"))
        self.assertIn("Не получилось", points.error_text("WAT"))
        self.assertIn("Профиль не найден", points.error_text("USER_NOT_FOUND"))

class PointsRenderHistoryTests(unittest.TestCase):
    def test_render_with_items(self):
        text = points.render_history({
            "balance": 90,
            "items": [
                {"delta": 90, "kind": "event_prize", "note": None},
                {"delta": -10, "kind": "event_fee", "note": "PvP <b>"}]
        })
        self.assertIn("Баланс: 90 PP", text)
        self.assertIn("+90 PP · приз ивента", text)
        self.assertIn("−10 PP · взнос в ивент — PvP <b>", text)

    def test_render_no_items(self):
        text = points.render_history({"balance": 50})
        self.assertIn("Операций пока нет.", text)

class PointsFeeLabelTests(unittest.TestCase):
    def test_fee_label_with_fee(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": 10}), "10 PP")

    def test_fee_label_zero(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": 0}), "бесплатно")

    def test_fee_label_empty(self):
        self.assertEqual(points.fee_label({}), "бесплатно")

    def test_fee_label_invalid(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": "x"}), "бесплатно")

if __name__ == "__main__":
    unittest.main()
