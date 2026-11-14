import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import cards  # noqa: E402
from services.ai import member_tools  # noqa: E402

UUID = "123e4567-e89b-12d3-a456-426614174000"


def callbacks(markup):
    return [b.callback_data for row in markup.inline_keyboard for b in row if b.callback_data]


class CardTests(unittest.TestCase):
    def test_callback_data_fits_telegram_limit(self):
        _, ev = cards.render(cards.event({"id": UUID, "title": "e"}))
        for data in callbacks(ev):
            self.assertLessEqual(len(data.encode()), 64)

    def test_event_card_hides_register_when_registered(self):
        _, markup = cards.render(cards.event({"id": UUID, "title": "e", "registered": True}))
        self.assertEqual(callbacks(markup), [])
        _, markup = cards.render(cards.event({"id": UUID, "title": "e", "registered": False}))
        self.assertEqual(callbacks(markup), [f"cd:evr:{UUID}"])

    def test_server_card(self):
        text, _ = cards.render(cards.server_status(True, 3, 20))
        self.assertIn("3 / 20", text)
        text, _ = cards.render(cards.server_status(False))
        self.assertIn("не на связи", text)


class ToolCardTests(unittest.IsolatedAsyncioTestCase):
    async def test_events_attach_cards(self):
        class R:
            error = None

            def __init__(self, data):
                self.data = data

        orig_events = member_tools.bot_list_events

        async def fake_events(*a, **k):
            return R([{"id": UUID, "title": "Ивент", "starts_at": "2026-12-01T18:00:00+00:00", "registered": False}])

        member_tools.bot_list_events = fake_events
        try:
            ctx = member_tools.Context(1, True, True)
            await member_tools.execute("list_events", {}, ctx)
            self.assertEqual(len(ctx.cards), 1)
        finally:
            member_tools.bot_list_events = orig_events


if __name__ == "__main__":
    unittest.main()
