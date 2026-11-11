import asyncio
import os
import sys
import unittest
from unittest import mock

os.environ.update(
    SUPABASE_URL="http://127.0.0.1:54321",
    SUPABASE_KEY="eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJlc2lnbmF0dXJl",
    BOT_TOKEN="1:x",
    MODERATION_GROUP_ID="-100123",
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.ai import admin_tools, ops  # noqa: E402


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


class OpsTests(unittest.TestCase):
    def test_unconfigured_names_the_missing_vars(self):
        with mock.patch.dict(os.environ, {"RENDER_API_KEY": "", "RENDER_SERVICE_ID": ""}):
            result = run(ops.render_status())
        self.assertIn("RENDER_API_KEY", result["error"])
        self.assertIn("RENDER_SERVICE_ID", result["error"])

    def test_render_status_whitelists_and_redacts(self):
        payload = [{"deploy": {"id": "dep-1", "status": "live", "commit": {"message": "fix token=abcdefgh123456"}, "secret": "x"}}]
        with mock.patch.dict(os.environ, {"RENDER_API_KEY": "k", "RENDER_SERVICE_ID": "srv-abc"}), \
             mock.patch.object(ops, "_request", mock.AsyncMock(return_value=(payload, None))):
            result = run(ops.render_status())
        text = str(result)
        self.assertNotIn("abcdefgh123456", text)
        self.assertNotIn("secret", text)
        self.assertEqual(result["deploys"][0]["status"], "live")

    def test_bad_ids_rejected_before_any_request(self):
        with mock.patch.dict(os.environ, {"VERCEL_TOKEN": "t", "VERCEL_PROJECT_ID": "p-123"}), \
             mock.patch.object(ops, "_request", mock.AsyncMock()) as req:
            self.assertIn("error", run(ops.vercel_deployment("../../etc")))
        req.assert_not_awaited()


class AdminOpsTools(unittest.TestCase):
    def test_redeploy_only_for_owner(self):
        ctx = admin_tools.Context(1)
        env = {"RENDER_API_KEY": "k", "RENDER_SERVICE_ID": "srv-abc"}
        with mock.patch.dict(os.environ, env), mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)):
            with mock.patch.object(admin_tools, "_is_owner", mock.AsyncMock(return_value=False)):
                self.assertIn("error", run(admin_tools.execute("propose_render_redeploy", {}, ctx)))
                self.assertEqual(ctx.cards, [])
            with mock.patch.object(admin_tools, "_is_owner", mock.AsyncMock(return_value=True)):
                self.assertIn("ok", run(admin_tools.execute("propose_render_redeploy", {}, ctx)))
        self.assertTrue(ctx.cards[0][1].inline_keyboard[0][0].callback_data.startswith("aio:rd:ok:"))

    def test_no_permission_blocks_ops_reads(self):
        with mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=False)):
            for name in ("render_status", "render_logs", "vercel_status", "github_status"):
                self.assertEqual(run(admin_tools.execute(name, {}, admin_tools.Context(1))), {"error": "no permission"})

    def test_announcement_needs_chat_configured(self):
        ctx = admin_tools.Context(1)
        with mock.patch.dict(os.environ, {"ANNOUNCE_CHAT_ID": ""}), \
             mock.patch.object(admin_tools, "_allowed", mock.AsyncMock(return_value=True)), \
             mock.patch.object(admin_tools, "_is_owner", mock.AsyncMock(return_value=True)):
            self.assertIn("ANNOUNCE_CHAT_ID", run(admin_tools.execute("propose_announcement", {"text": "Привет всем!"}, ctx))["error"])


if __name__ == "__main__":
    unittest.main()
