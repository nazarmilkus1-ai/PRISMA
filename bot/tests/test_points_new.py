import unittest
import os
import sys

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import points

class PointsNewTests(unittest.TestCase):
    def test_parse_amount_variants(self):
        self.assertEqual(points.parse_amount("1000"), 1000)
        self.assertEqual(points.parse_amount("+200"), 200)
        self.assertEqual(points.parse_amount("-50"), -50)
        self.assertIsNone(points.parse_amount("abc"))
        self.assertIsNone(points.parse_amount("1.5"))
        self.assertIsNone(points.parse_amount(""))
        self.assertIsNone(points.parse_amount("   "))
        self.assertEqual(points.parse_amount("  0  "), 0)
        self.assertEqual(points.parse_amount("+0"), 0)
        self.assertIsNone(points.parse_amount(None))

    def test_render_history_simple(self):
        data = {
            "balance": 1000,
            "items": [
                {"delta": 100, "kind": "transfer_in", "note": "пополнение"},
                {"delta": -50, "kind": "shop", "note": "покупка"},
            ],
        }
        result = points.render_history(data)
        self.assertIn("Баланс: 1 000 PP", result)
        self.assertIn("+100 PP", result)
        self.assertIn("−50 PP", result)
        self.assertIn("пополнение", result)
        self.assertIn("покупка", result)

    def test_fee_label(self):
        row = {"entry_fee_pp": "10"}
        self.assertEqual(points.fee_label(row), "10 PP")
        row = {"entry_fee_pp": "0"}
        self.assertEqual(points.fee_label(row), "бесплатно")
