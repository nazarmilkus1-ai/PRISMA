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


class LiveCardTests(unittest.TestCase):
    def test_events_card_has_register_buttons_and_site_link(self):
        rows = [{"id": "11111111-1111-1111-1111-111111111111", "title": "Битва кланов", "starts_at": "2026-11-14", "registered": False},
                {"id": "22222222-2222-2222-2222-222222222222", "title": "Спавн-ран", "starts_at": "2026-11-15", "registered": True}]
        with mock.patch.object(live, "list_events", mock.AsyncMock(return_value=(rows, None))):
            text, markup = run(live.live_card("какие ближайшие ивенты", 1, True, private=True))
        data = [b.callback_data for row in markup.inline_keyboard for b in row if b.callback_data]
        self.assertEqual(data, ["cd:evr:11111111-1111-1111-1111-111111111111"])  # registered one has no button
        self.assertTrue(any(b.url and b.url.endswith("/events") for row in markup.inline_keyboard for b in row))
        self.assertIn("✅", text)

    def test_locked_and_error_answers_have_no_buttons(self):
        text, markup = run(live.live_card("мой клан", 1, False, private=True))
        self.assertTrue(text.startswith("🔒"))
        self.assertIsNone(markup)

    def test_online_card_links_to_site(self):
        with mock.patch.object(live, "_online", mock.AsyncMock(return_value="ONLINE")):
            text, markup = run(live.live_card("кто онлайн", 1, False, private=False))
        self.assertEqual(text, "ONLINE")
        self.assertTrue(any(b.url and b.url.endswith("/status") for row in markup.inline_keyboard for b in row))
