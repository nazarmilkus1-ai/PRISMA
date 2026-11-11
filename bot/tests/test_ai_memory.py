import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.ai import memory 


class MemoryTests(unittest.TestCase):
    def setUp(self):
        memory.forget(1, 2)

    def test_history_keeps_last_messages(self):
        for i in range(20):
            memory.remember(1, 2, "user", f"q{i}")
        h = memory.history(1, 2)
        self.assertEqual(len(h), memory.MAX_MESSAGES)
        self.assertEqual(h[-1]["content"], "q19")

    def test_rating_is_visible_to_model(self):
        aid = memory.new_answer_id()
        memory.remember(1, 2, "assistant", "ответ", answer_id=aid)
        memory.set_rating(1, 2, aid, 1)
        self.assertIn("👍", memory.history(1, 2)[0]["content"])
        memory.set_rating(1, 2, aid, -1)
        self.assertIn("👎", memory.history(1, 2)[0]["content"])

    def test_other_user_rating_does_not_touch(self):
        aid = memory.new_answer_id()
        memory.remember(1, 2, "assistant", "ответ", answer_id=aid)
        memory.set_rating(1, 3, aid, 1)
        self.assertNotIn("👍", memory.history(1, 2)[0]["content"])

    def test_expired_messages_dropped(self):
        memory.remember(1, 2, "user", "old", now=1000.0)
        self.assertEqual(memory.history(1, 2, now=1000.0 + memory.TTL_SECONDS + 1), [])


if __name__ == "__main__":
    unittest.main()
