import asyncio
import os
import sys
import types
import unittest
from unittest import mock

os.environ.update(
    SUPABASE_URL="http://127.0.0.1:54321",
    SUPABASE_KEY="eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJlc2lnbmF0dXJl",
    BOT_TOKEN="1:x",
    MODERATION_GROUP_ID="-100123",
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from keyboards.admin_panel import home_keyboard, section_keyboard  # noqa: E402
from services import admin_dashboard  # noqa: E402


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def data(callbacks):
    return {b.callback_data for row in callbacks.inline_keyboard for b in row if b.callback_data}


class KeyboardTests(unittest.TestCase):
    def test_badges_and_url(self):
        kb = home_keyboard({"applications": 3, "reports": 0}, ["*"], "https://panel.example")
        texts = [b.text for row in kb.inline_keyboard for b in row]
        self.assertIn("📋 Заявки (3)", texts)
        self.assertIn("📢 Репорты", texts)
        self.assertTrue(any(b.url == "https://panel.example" for row in kb.inline_keyboard for b in row))

    def test_sections_follow_permissions(self):
        limited = data(home_keyboard({}, ["report.view"], None))
        self.assertIn("admin:reports", limited)
        self.assertNotIn("admin:applications", limited)
        self.assertNotIn("ap:sys", limited)
        self.assertIn("mode:participant", limited)

    def test_unknown_perms_show_everything_and_callbacks_short(self):
        everything = home_keyboard(None, None, None)
        for row in everything.inline_keyboard:
            for b in row:
                if b.callback_data:
                    self.assertLessEqual(len(b.callback_data.encode()), 64)
        self.assertIn("ap:sys", data(everything))
        self.assertIn("ap:home", data(section_keyboard("sys")))


class DashboardTests(unittest.TestCase):
    def test_snapshot_only_fetches_permitted_queues(self):
        ok = types.SimpleNamespace(data={"status": "online"}, error=None)
        with mock.patch.object(admin_dashboard, "pending_applications", mock.AsyncMock(return_value=([1, 2], None))) as apps, \
             mock.patch.object(admin_dashboard, "open_reports", mock.AsyncMock(return_value=([], None))) as reports, \
             mock.patch.object(admin_dashboard, "bot_get_server_status", mock.AsyncMock(return_value=ok)), \
             mock.patch.object(admin_dashboard, "get_server_metrics", mock.AsyncMock(return_value=({"max_players": 20}, None))), \
             mock.patch.object(admin_dashboard, "get_online_players", mock.AsyncMock(return_value=([{}, {}, {}], None))):
            snap = run(admin_dashboard.snapshot(1, ["application.view"]))
        apps.assert_awaited()
        reports.assert_not_awaited()
        self.assertEqual(snap["applications"], 2)
        self.assertNotIn("reports", snap)
        self.assertEqual((snap["online"], snap["max_players"], snap["server"]), (3, 20, "online"))

    def test_failed_lookup_is_unknown_not_zero(self):
        text = admin_dashboard.render_home("Owner", ["*"], {"applications": None, "reports": 4, "server": None})
        self.assertIn("заявки <b>?</b>", text)
        self.assertIn("репорты <b>4</b>", text)
        self.assertIn("НЕТ ДАННЫХ", text)


if __name__ == "__main__":
    unittest.main()
