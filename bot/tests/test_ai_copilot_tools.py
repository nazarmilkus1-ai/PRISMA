import asyncio
import types
import unittest
from unittest import mock

from services.ai import admin_tools, diagnostics
from utils.mdhtml import strip_markdown, to_telegram_html


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


def ok(data):
    return types.SimpleNamespace(data=data, error=None)


class MarkdownTests(unittest.TestCase):
    def test_bold_code_bullets(self):
        out = to_telegram_html("**Игрок** `.Nick`\n- один\n* два")
        self.assertEqual(out, "<b>Игрок</b> <code>.Nick</code>\n• один\n• два")

    def test_html_is_escaped(self):
        out = to_telegram_html("<script>x</script> **a<b**")
        self.assertNotIn("<script>", out)
        self.assertIn("&lt;script&gt;", out)

    def test_code_content_not_formatted(self):
        self.assertEqual(to_telegram_html("`**x**`"), "<code>**x**</code>")

    def test_link_and_plain_fallback(self):
        self.assertIn('<a href="https://a.b/c">t</a>', to_telegram_html("[t](https://a.b/c)"))
        self.assertEqual(strip_markdown("**a** `b`"), "a b")


class DiagnosticsTests(unittest.TestCase):
    def test_redacts_secrets(self):
        text = diagnostics.redact("key sk-abcdef123456789 token=abcdefgh1234 ok")
        self.assertNotIn("sk-abcdef", text)
        self.assertNotIn("abcdefgh1234", text)
        self.assertIn("ok", text)

    def test_issue_not_configured(self):
        with mock.patch.dict("os.environ", {"GITHUB_TOKEN": "", "GITHUB_REPO": ""}):
            self.assertFalse(diagnostics.issue_configured())
            self.assertEqual(run(diagnostics.create_issue("t", "b"))[1], "not configured")


class GroupMembershipTests(unittest.TestCase):
    def test_counts_in_and_out_of_group(self):
        rows = [{"display_name": "A", "username": "a", "telegram_id": 1, "nickname": ".A"},
                {"display_name": "B", "username": "b", "telegram_id": 2, "nickname": ".B"},
                {"display_name": "J", "username": "j", "telegram_id": 3, "nickname": "Java"}]

        class FakeBot:
            async def get_chat_member(self, chat, tg_id):
                if tg_id == 2:
                    raise RuntimeError("user not found")
                return types.SimpleNamespace(status="member")

        ctx = admin_tools.Context(1, FakeBot())
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)), \
             mock.patch.object(admin_tools, "bot_list_current_participants", mock.AsyncMock(return_value=ok(rows))), \
             mock.patch("config.MODERATION_GROUP_ID", -100123):
            result = run(admin_tools.execute("group_membership", {"platform": "bedrock"}, ctx))
        self.assertEqual(result["total"], 2)
        self.assertEqual([p["nickname"] for p in result["in_group"]], [".A"])
        self.assertEqual([p["nickname"] for p in result["unknown"]], [".B"])
        self.assertEqual(result["not_in_group"], [])

    def test_needs_bot_and_group(self):
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)):
            self.assertIn("error", run(admin_tools.execute("group_membership", {}, admin_tools.Context(1))))


class ToolTests(unittest.TestCase):
    def _ctx(self):
        return admin_tools.Context(1)

    def test_no_permission_blocks_new_tools(self):
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=False)):
            for name in ("server_status", "player_card", "recent_errors", "report_bug", "propose_punishment"):
                self.assertEqual(run(admin_tools.execute(name, {}, self._ctx())), {"error": "no permission"})

    def test_player_card_returns_last_activity(self):
        row = {"minecraft_nickname": ".Nick", "telegram_id": 5}
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)), \
             mock.patch.object(admin_tools, "find_players", mock.AsyncMock(return_value=([row], None))), \
             mock.patch.object(admin_tools, "bot_get_player_activity_stats", mock.AsyncMock(return_value=ok({"last_activity": "2026-11-09"}))):
            result = run(admin_tools.execute("player_card", {"query": "Nick"}, self._ctx()))
        self.assertEqual(result["activity"]["last_activity"], "2026-11-09")

    def test_punishment_is_only_a_command_card(self):
        row = {"minecraft_nickname": "Bad", "telegram_id": 9}
        ctx = self._ctx()
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)), \
             mock.patch.object(admin_tools, "find_players", mock.AsyncMock(return_value=([row], None))):
            result = run(admin_tools.execute("propose_punishment", {"query": "Bad", "kind": "mute", "reason": "spam", "duration": "2h"}, ctx))
        self.assertIn("ok", result)
        self.assertIn("/mute Bad spam 2h", ctx.cards[0][0])
        self.assertIsNone(ctx.cards[0][1])

    def test_support_resolve_card_needs_open_ticket(self):
        ctx = self._ctx()
        data = {"success": True, "items": [{"ticket_no": 7, "message": "help"}]}
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)), \
             mock.patch.object(admin_tools, "bot_list_support_requests", mock.AsyncMock(return_value=ok(data))):
            self.assertIn("ok", run(admin_tools.execute("propose_support_resolve", {"ticket_no": 7}, ctx)))
            self.assertIn("error", run(admin_tools.execute("propose_support_resolve", {"ticket_no": 8}, self._ctx())))
        self.assertEqual(ctx.cards[0][1].inline_keyboard[0][0].callback_data, "adm:sup:res:7")


if __name__ == "__main__":
    unittest.main()
