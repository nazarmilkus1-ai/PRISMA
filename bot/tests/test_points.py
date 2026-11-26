from __future__ import annotations

import unittest

from services import points


class PointsTextTests(unittest.TestCase):
    def test_fmt(self):
        self.assertEqual(points.fmt(1234), "1 234")
        self.assertEqual(points.fmt(0), "0")
        self.assertEqual(points.fmt(-5), "-5")
        self.assertEqual(points.fmt("100"), "100")
        self.assertEqual(points.fmt(None), "0")
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")
        self.assertEqual(points.fmt(5), "5")
        self.assertEqual(points.fmt(99), "99")
        self.assertEqual(points.fmt(None), "0")
        self.assertEqual(points.fmt(999999999999), "999 999 999 999")
        self.assertEqual(points.fmt(5), "5")
        self.assertEqual(points.fmt(99), "99")

    def test_history_render(self):
        text = points.render_history({"balance": 90, "items": [
            {"delta": 90, "kind": "event_prize", "note": None},
            {"delta": -10, "kind": "event_fee", "note": "PvP <b>"}]})
        self.assertIn("Баланс: 90 PP", text)
        self.assertIn("+90 PP · приз ивента", text)
        self.assertIn("−10 PP · взнос в ивент — PvP <b>", text)

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
        self.assertFalse(points.has_error("ERROR: INSUFFICIENT_PP", "OTHER"))
        self.assertFalse(points.has_error("something else", "INSUFFICIENT_PP"))


class ParseAmountTests(unittest.TestCase):
    def test_parse_valid(self):
        self.assertEqual(points.parse_amount("50"), 50)
        self.assertEqual(points.parse_amount("  100  "), 100)
        self.assertEqual(points.parse_amount("+50"), 50)
        self.assertEqual(points.parse_amount("-10"), -10)
        self.assertEqual(points.parse_amount("1 000"), 1000)
        self.assertEqual(points.parse_amount("100000"), 100000)

    def test_parse_invalid(self):
        self.assertIsNone(points.parse_amount(None))
        self.assertIsNone(points.parse_amount(""))
        self.assertIsNone(points.parse_amount("abc"))
        self.assertIsNone(points.parse_amount("50.5"))
        self.assertIsNone(points.parse_amount("100001"))
        self.assertIsNone(points.parse_amount("-100001"))
        self.assertIsNone(points.parse_amount("+"))
        self.assertIsNone(points.parse_amount("-"))
        self.assertIsNone(points.parse_amount("  "))

    def test_parse_edge_cases(self):
        # Plus sign without digits
        self.assertIsNone(points.parse_amount("+"))
        # Large number
        self.assertIsNone(points.parse_amount("999999999999999999999"))
        # Leading zeros
        self.assertEqual(points.parse_amount("0050"), 50)
        # Boolean-like strings
        self.assertIsNone(points.parse_amount("true"))
        self.assertIsNone(points.parse_amount("false"))


class ErrorTextTests(unittest.TestCase):
    def test_known_codes(self):
        self.assertIn("Профиль не найден", points.error_text("USER_NOT_FOUND"))
        self.assertIn("Не нашёл такого игрока", points.error_text("TARGET_NOT_FOUND"))
        self.assertIn("Себе переводить нельзя", points.error_text("SELF_TRANSFER"))
        self.assertIn("Сумма должна быть целым числом", points.error_text("INVALID_AMOUNT"))
        self.assertIn("Только участники с одобренной заявкой", points.error_text("NOT_A_MEMBER"))
        self.assertIn("Не хватает PP", points.error_text("INSUFFICIENT_PP"))
        self.assertIn("Нет права управлять PP", points.error_text("PERMISSION_DENIED"))
        self.assertIn("Событие не найдено", points.error_text("EVENT_NOT_FOUND"))
        self.assertIn("Взносы уже оплачены", points.error_text("FEES_ALREADY_PAID"))
        self.assertIn("Приз за это событие уже выплачен", points.error_text("ALREADY_PAID"))
        self.assertIn("Победитель должен быть участником", points.error_text("WINNER_NOT_PARTICIPANT"))

    def test_unknown_code(self):
        self.assertEqual(points.error_text("UNKNOWN_CODE"), "Не получилось. Попробуй позже.")
        self.assertEqual(points.error_text(123), "Не получилось. Попробуй позже.")
        self.assertEqual(points.error_text(None), "Не получилось. Попробуй позже.")


class FeeLabelTests(unittest.TestCase):
    def test_various_inputs(self):
        self.assertEqual(points.fee_label({"entry_fee_pp": 10}), "10 PP")
        self.assertEqual(points.fee_label({"entry_fee_pp": 0}), "бесплатно")
        self.assertEqual(points.fee_label({}), "бесплатно")
        self.assertEqual(points.fee_label({"entry_fee_pp": "x"}), "бесплатно")
        self.assertEqual(points.fee_label({"entry_fee_pp": 1000}), "1 000 PP")
        self.assertEqual(points.fee_label({"entry_fee_pp": -5}), "бесплатно")
        self.assertEqual(points.fee_label(None), "бесплатно")
        self.assertEqual(points.fee_label("not a dict"), "бесплатно")


class HasErrorTests(unittest.TestCase):
    def test_matches_exception_text(self):
        self.assertTrue(points.has_error("ERROR: INSUFFICIENT_PP", "INSUFFICIENT_PP"))
        self.assertFalse(points.has_error("ERROR: INSUFFICIENT_PP", "OTHER"))
        self.assertFalse(points.has_error("something else", "INSUFFICIENT_PP"))
        self.assertTrue(points.has_error("INSUFFICIENT_PP", "INSUFFICIENT_PP"))
        self.assertTrue(points.has_error("PostgreSQL error: INSUFFICIENT_PP", "INSUFFICIENT_PP"))
        self.assertFalse(points.has_error("PostgreSQL error: OTHER", "INSUFFICIENT_PP"))
