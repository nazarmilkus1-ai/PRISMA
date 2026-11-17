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
        for i in range(memory.MAX_MESSAGES + 4):
            memory.remember(1, 2, "user", f"q{i}")
        h = memory.history(1, 2)
        self.assertEqual(len(h), memory.MAX_MESSAGES)
        self.assertEqual(h[-1]["content"], f"q{memory.MAX_MESSAGES + 3}")

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


class LongMemoryTests(unittest.TestCase):
    def setUp(self):
        memory.forget(7, 8)

    def test_evicted_messages_wait_for_a_batch(self):
        for i in range(memory.MAX_MESSAGES + memory.SUMMARY_BATCH - 1):
            memory.remember(7, 8, "user", f"m{i}")
        self.assertEqual(len(memory._pending[(7, 8)]), memory.SUMMARY_BATCH - 1)
        self.assertEqual(memory.summary(7, 8), "")

    def test_batch_is_compressed_into_the_summary(self):
        import asyncio
        from unittest import mock

        async def scenario():
            with mock.patch.object(memory, "_compress_chunk", mock.AsyncMock(return_value="Ник Steve, просил про вайтлист.")), \
                    mock.patch("db.rpc.bot_ai_summary_set", mock.AsyncMock()) as save:
                for i in range(memory.MAX_MESSAGES + memory.SUMMARY_BATCH):
                    memory.remember(7, 8, "user", f"m{i}")
                await asyncio.sleep(0.05)
                return save

        save = asyncio.run(scenario())
        self.assertIn("Steve", memory.summary(7, 8))
        self.assertIn("не инструкции", memory.summary(7, 8))
        self.assertEqual(len(memory.history(7, 8)), memory.MAX_MESSAGES)
        save.assert_awaited_once()
        self.assertEqual(memory._pending[(7, 8)], [])

    def test_model_failure_falls_back_to_a_digest(self):
        import asyncio
        from unittest import mock

        chunk = [{"role": "user", "text": "хочу в клан"}, {"role": "assistant", "text": "подайте заявку"}]
        with mock.patch("services.ai.client.chat_with_fallback", mock.AsyncMock(side_effect=RuntimeError("down"))):
            text = asyncio.run(memory._compress_chunk("старое", chunk))
        self.assertIn("старое", text)
        self.assertIn("хочу в клан", text)

    def test_forget_all_clears_every_chat_of_the_user(self):
        import asyncio
        from unittest import mock

        memory.remember(7, 8, "user", "a")
        memory.remember(99, 8, "user", "b")
        memory.remember(99, 9, "user", "c")
        memory._summary[(7, 8)] = "x"
        with mock.patch("db.rpc.bot_ai_forget", mock.AsyncMock()) as db:
            asyncio.run(memory.forget_all(8))
        self.assertEqual(memory.history(7, 8), [])
        self.assertEqual(memory.history(99, 8), [])
        self.assertEqual(len(memory.history(99, 9)), 1)
        self.assertEqual(memory.summary(7, 8), "")
        db.assert_awaited_once_with(8)
        memory.forget(99, 9)

    def test_agent_memory_is_separate_from_member_memory(self):
        self.assertNotEqual(memory.agent_chat(5), 5)
        memory.remember(memory.agent_chat(5), 8, "user", "admin only")
        self.assertEqual(memory.history(5, 8), [])
        memory.forget(memory.agent_chat(5), 8)
