import os
import sys
import unittest

os.environ.update(
    SUPABASE_URL="http://127.0.0.1:54321",
    SUPABASE_KEY="eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJlc2lnbmF0dXJl",
    BOT_TOKEN="1:x",
    MODERATION_GROUP_ID="-100123",
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from keyboards.inline import main_menu_approved  # noqa: E402
from services import quick  # noqa: E402


def cbs(kb):
    return [b.callback_data for row in kb.inline_keyboard for b in row]


class QuickTests(unittest.TestCase):
    def setUp(self):
        quick._usage.clear()

    def test_defaults_when_new(self):
        data = cbs(quick.keyboard(1))
        self.assertEqual(data[:3], list(quick.DEFAULTS[:3]))
        self.assertIn("menu:back", data)

    def test_frequent_first_and_no_duplicates(self):
        for _ in range(3):
            quick.record(1, "market")
        quick.record(1, "news")
        data = cbs(quick.keyboard(1))
        self.assertEqual(data[0], "market")
        self.assertEqual(data[1], "news")
        self.assertEqual(len(data), len(set(data)))

    def test_ignores_unknown_callbacks_and_isolates_users(self):
        quick.record(1, "adm:rep:ok:uuid")
        quick.record(2, "market")
        self.assertEqual(quick.top(1), [])
        self.assertEqual(quick.top(2), ["market"])

    def test_bounded_memory(self):
        for uid in range(quick.MAX_USERS + 10):
            quick.record(uid, "market")
        self.assertLessEqual(len(quick._usage), quick.MAX_USERS)

    def test_every_quick_action_callback_is_a_real_menu_target(self):
        menu = set(cbs(main_menu_approved())) | {"player:stats", "player:achievements", "player:notifications"}
        self.assertTrue(set(quick.ACTIONS) <= menu)
        self.assertIn("quick", menu)


if __name__ == "__main__":
    unittest.main()
