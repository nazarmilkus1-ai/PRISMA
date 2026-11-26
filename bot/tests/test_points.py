import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points


class PointsTextTests(unittest.TestCase):
    def test_parse_amount(self):
        self.assertEqual(points.parse_amount("50"), 50)
        self.assertEqual(points.parse_amount("+100"), 100)
        self.assertEqual(points.parse_amount("-7"), -7)
        self.assertIsNone(points.parse_amount("abc"))
        self.assertIsNone(points.parse_amount("1.5"))

    def test_fmt_groups_thousands(self):
        self.assertEqual(points.fmt(1234567), "1 234 567")
        self.assertEqual(points.fmt(None), "0")

    def test_history_render(self):
        text = points.render_history({"balance": 90, "items": [
            {"delta": 90, "kind": "event_prize", "note": None},
            {"delta": -10, "kind": "event_fee", "note": "PvP <b>"}]})
        self.assertIn("Баланс: 90 PP", text)
        self.assertIn("+90 PP · приз ивента", text)
        self.assertIn("−10 PP · взнос в ивент — PvP &lt;b&gt;", text)

    def test_unknown_error_is_generic(self):
        self.assertIn("Не хватает", points.error_text("INSUFFICIENT_PP"))
        self.assertIn("Не получилось", points.error_text("WAT"))


if __name__ == "__main__":
    unittest.main()


class EventFeeTexts(unittest.TestCase):
    def test_fee_label(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": 10}), "10 PP")
        self.assertEqual(points.fee_label({"entry_fee_pp": 0}), "бесплатно")
        self.assertEqual(points.fee_label({}), "бесплатно")
        self.assertEqual(points.fee_label({"entry_fee_pp": "x"}), "бесплатно")

    def test_has_error_matches_exception_text(self):
        self.assertTrue(points.has_error("ERROR: INSUFFICIENT_PP", "INSUFFICIENT_PP"))
        self.assertFalse(points.has_error("EVENT_FULL", "INSUFFICIENT_PP"))

    def test_event_errors_have_texts(self):
        for code in ("ALREADY_PAID", "WINNER_NOT_PARTICIPANT", "FEES_ALREADY_PAID", "EVENT_NOT_FOUND"):
            self.assertNotEqual(points.error_text(code), points.error_text("nope"))
