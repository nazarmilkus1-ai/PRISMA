import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
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

    def test_parse_amount_edge_cases(self):
        # Empty string
        self.assertIsNone(points.parse_amount(""))
        # String with only spaces
        self.assertIsNone(points.parse_amount("   "))
        # Float as string
        self.assertIsNone(points.parse_amount("3.14"))
        # String with leading/trailing spaces
        self.assertEqual(points.parse_amount("  50  "), 50)
        # Zero
        self.assertEqual(points.parse_amount("0"), 0)
        # Positive sign only
        self.assertEqual(points.parse_amount("+0"), 0)
        # None input
        self.assertIsNone(points.parse_amount(None))
        # Negative float as string
        self.assertIsNone(points.parse_amount("-3.14"))
        # String with only minus
        self.assertIsNone(points.parse_amount("-"))
        # Unicode digits
        self.assertIsNone(points.parse_amount("５０"))
        # None input
        self.assertIsNone(points.parse_amount(None))
        # Negative float as string
        self.assertIsNone(points.parse_amount("-3.14"))
        # String with only minus
        self.assertIsNone(points.parse_amount("-"))
        # Unicode digits
        self.assertIsNone(points.parse_amount("５０"))
        # Boolean string
        self.assertIsNone(points.parse_amount("True"))
        # Empty with plus
        self.assertIsNone(points.parse_amount("+"))

    def test_fmt_groups_thousands(self):
        self.assertEqual(points.fmt(1234567), "1 234 567")
        self.assertEqual(points.fmt(None), "0")

    def test_fmt_edge_cases(self):
        # Negative number
        self.assertEqual(points.fmt(-1234567), "-1 234 567")
        # Zero
        self.assertEqual(points.fmt(0), "0")
        # Small positive number
        self.assertEqual(points.fmt(100), "100")
        # Large number
        self.assertEqual(points.fmt(999999999), "999 999 999")
        # Float value (should be converted to int)
        self.assertEqual(points.fmt(1234.56), "1 234")
        # None input
        self.assertEqual(points.fmt(None), "0")
        # Very large number
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")
        # Single digit
        self.assertEqual(points.fmt(5), "5")
        # Two digits
        self.assertEqual(points.fmt(99), "99")
        # None input
        self.assertEqual(points.fmt(None), "0")
        # Very large number
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")
        # Single digit
        self.assertEqual(points.fmt(5), "5")
        # Two digits
        self.assertEqual(points.fmt(99), "99")

    def test_history_render(self):
        text = points.render_history({"balance": 90, "items": [
            {"delta": 90, "kind": "event_prize", "note": None},
            {"delta": -10, "kind": "event_fee", "note": "PvP <b>"}]})
        self.assertIn("Баланс: 90 PP", text)
        self.assertIn("+90 PP · приз ивента", text)
        self.assertIn("−10 PP · взнос в ивент — PvP <b>", text)

    def test_history_render_empty(self):
        # Empty history - no items
        text = points.render_history({"balance": 0, "items": []})
        self.assertIn("Баланс: 0 PP", text)
        self.assertIn("Операций пока нет", text)

    def test_history_render_none_items(self):
        # None items should be treated as empty
        text = points.render_history({"balance": 100, "items": None})
        self.assertIn("Баланс: 100 PP", text)
        self.assertIn("Операций пока нет", text)

    def test_history_render_negative_balance(self):
        # Negative balance
        text = points.render_history({"balance": -50, "items": []})
        self.assertIn("Баланс: -50 PP", text)

    def test_history_render_unknown_kind(self):
        # Unknown operation kind should show the kind as-is
        text = points.render_history({"balance": 0, "items": [
            {"delta": 10, "kind": "unknown_kind", "note": None}]})
        self.assertIn("+10 PP · unknown_kind", text)

    def test_history_render_html_escaping(self):
        # HTML in notes should be escaped
        text = points.render_history({"balance": 0, "items": [
            {"delta": 5, "kind": "reward", "note": "<script>alert(1)</script>"}]})
        self.assertIn("<script>alert(1)</script>", text)
        self.assertNotIn("<script>", text)

    def test_history_render_special_chars_in_note(self):
        # Special characters in note should be escaped
        text = points.render_history({"balance": 0, "items": [
            {"delta": 5, "kind": "reward", "note": "A & B < C > D"}]})
        self.assertIn("A & B < C > D", text)

    def test_history_render_large_numbers(self):
        # Large numbers should be formatted with spaces
        text = points.render_history({"balance": 1000000, "items": [
            {"delta": 1000000, "kind": "event_prize", "note": None}]})
        self.assertIn("Баланс: 1 000 000 PP", text)
        self.assertIn("+1 000 000 PP", text)

    def test_history_render_zero_delta(self):
        # Zero delta should show as +0
        text = points.render_history({"balance": 0, "items": [
            {"delta": 0, "kind": "admin", "note": "корректировка"}]})
        self.assertIn("+0 PP · корректировка", text)

    def test_history_render_missing_delta(self):
        # Missing delta should default to 0
        text = points.render_history({"balance": 0, "items": [
            {"kind": "reward", "note": "без дельты"}]})
        self.assertIn("+0 PP · награда", text)

    def test_history_render_missing_kind(self):
        # Missing kind should show as empty string or "None"
        text = points.render_history({"balance": 0, "items": [
            {"delta": 10, "note": "нет вида"}]})
        self.assertIn("+10 PP · None", text)

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