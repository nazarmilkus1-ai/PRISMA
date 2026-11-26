import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points


class PointsEdgeCaseTests(unittest.TestCase):
    def test_parse_amount_whitespace_only(self):
        self.assertIsNone(points.parse_amount("   "))

    def test_parse_amount_float_string(self):
        self.assertIsNone(points.parse_amount("3.14"))

    def test_parse_amount_leading_zeros(self):
        self.assertEqual(points.parse_amount("007"), 7)

    def test_parse_amount_boolean_string(self):
        self.assertIsNone(points.parse_amount("True"))

    def test_parse_amount_none(self):
        self.assertIsNone(points.parse_amount(None))

    def test_parse_amount_empty_string(self):
        self.assertIsNone(points.parse_amount(""))

    def test_parse_amount_plus_only(self):
        self.assertIsNone(points.parse_amount("+"))

    def test_parse_amount_plus_spaces(self):
        self.assertIsNone(points.parse_amount(" + "))

    def test_parse_amount_very_large(self):
        self.assertEqual(points.parse_amount("999999999999"), 999999999999)

    def test_parse_amount_comma(self):
        self.assertIsNone(points.parse_amount("1,000"))

    def test_fmt_negative(self):
        self.assertEqual(points.fmt(-1234567), "-1 234 567")

    def test_fmt_zero(self):
        self.assertEqual(points.fmt(0), "0")

    def test_fmt_small_positive(self):
        self.assertEqual(points.fmt(100), "100")

    def test_fmt_large_number(self):
        self.assertEqual(points.fmt(999999999), "999 999 999")

    def test_fmt_float_converted(self):
        self.assertEqual(points.fmt(1234.56), "1 234")

    def test_fmt_none(self):
        self.assertEqual(points.fmt(None), "0")

    def test_fmt_very_large(self):
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")

    def test_fmt_single_digit(self):
        self.assertEqual(points.fmt(5), "5")

    def test_fmt_two_digits(self):
        self.assertEqual(points.fmt(99), "99")

    def test_render_history(self):
        text = points.render_history({"balance": 90, "items": [
            {"delta": 90, "kind": "event_prize", "note": None},
            {"delta": -10, "kind": "event_fee", "note": "PvP <b>"}]})
        self.assertIn("Баланс: 90 PP", text)
        self.assertIn("+90 PP · приз ивента", text)
        self.assertIn("−10 PP · взнос в ивент — PvP <b>", text)

    def test_error_text_insufficient(self):
        self.assertIn("Не хватает", points.error_text("INSUFFICIENT_PP"))

    def test_error_text_unknown(self):
        self.assertIn("Не получилось", points.error_text("WAT"))

    def test_fee_label_default(self):
        self.assertEqual(points.fee_label({}), "бесплатно")

    def test_fee_label_zero(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": 0}), "бесплатно")

    def test_fee_label_string_x(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": "x"}), "бесплатно")

    def test_has_error_match(self):
        self.assertTrue(points.has_error("ERROR: INSUFFICIENT_PP", "INSUFFICIENT_PP"))

    def test_has_error_no_match(self):
        self.assertFalse(points.has_error("EVENT_FULL", "INSUFFICIENT_PP"))

    def test_event_errors_not_equal(self):
        for code in ("ALREADY_PAID", "WINNER_NOT_PARTICIPANT", "FEES_ALREADY_PAID", "EVENT_NOT_FOUND"):
            self.assertNotEqual(points.error_text(code), points.error_text("nope"))


if __name__ == "__main__":
    unittest.main()