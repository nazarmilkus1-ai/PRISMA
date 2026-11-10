import asyncio
import unittest
from unittest import mock

from services.ai import live


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


class LiveTests(unittest.TestCase):
    def test_intents(self):
        self.assertEqual(live.live_intent("кто сейчас онлайн?"), ("online", False))
        self.assertEqual(live.live_intent("покажи мою статистику"), ("stats", True))
        self.assertEqual(live.live_intent("в каком я клане"), ("clan", True))
        self.assertEqual(live.live_intent("почему я в бане"), ("punish", True))
        self.assertEqual(live.live_intent("какие есть ивенты"), ("events", False))
        self.assertIsNone(live.live_intent("что такое призма"))

    def test_personal_data_never_in_groups(self):
        with mock.patch.object(live, "_stats", mock.AsyncMock(return_value="SECRET")) as stats:
            text = run(live.live_answer("моя статистика", 1, True, private=False))
        stats.assert_not_called()
        self.assertIn("личных сообщениях", text)

    def test_members_only(self):
        text = run(live.live_answer("мой клан", 1, False, private=True))
        self.assertIn("после одобрения", text)

    def test_online_open_to_guests(self):
        with mock.patch.object(live, "_online", mock.AsyncMock(return_value="ONLINE")):
            self.assertEqual(run(live.live_answer("кто онлайн", 1, False, private=False)), "ONLINE")


if __name__ == "__main__":
    unittest.main()
