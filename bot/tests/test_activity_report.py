import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import activity_report


def row(cat, user, name="x", silent=None):
    return {"category": cat, "username": user, "name": name, "tg_id": 1, "days_silent": silent}


class RenderTests(unittest.TestCase):
    def test_sections_and_counts(self):
        text = activity_report.render([
            row("member_silent", "a", "A", 12.4), row("member_never_wrote", "b", "B"),
            row("guest_silent", "c", "C", 30), row("guest_never_wrote", "d", "D"),
            row("member_active", "e"), row("staff", "f"),
        ], 7)
        self.assertIn("Участников (одобрены): <b>3</b>", text)
        self.assertIn("Подали заявку и неактивны: <b>2</b>", text)
        self.assertIn("не подали и неактивны: <b>2</b>", text)
        self.assertIn("@a — A (12 дн.)", text)
        self.assertIn("ни разу не писали", text)
        self.assertNotIn("@e", text)  # active people are not listed

    def test_empty(self):
        self.assertIn("Участников (одобрены): <b>0</b>", activity_report.render([], 7))


if __name__ == "__main__":
    unittest.main()
