"""Run: cd bot && python -m unittest discover -s tests -v   (no network, no database)."""
import os
import sys
import types
import unittest

os.environ.update(
    SUPABASE_URL="http://127.0.0.1:54321",
    SUPABASE_KEY="eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJlc2lnbmF0dXJl",
    BOT_TOKEN="1:x",
    MODERATION_GROUP_ID="-100123",
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from handlers import admin_actions, ai as ai_handler  # noqa: E402
from handlers.guide import build_guide  # noqa: E402
from services.ai import admin_tools, navigator  # noqa: E402


class Result:
    def __init__(self, data=None, error=None):
        self.data, self.error = data, error


class Callback:
    def __init__(self, data):
        self.data = data
        self.alerts = []
        self.from_user = types.SimpleNamespace(id=9, full_name="Mod")
        self.message = None

    async def answer(self, text=None, **_):
        self.alerts.append(text)


class NavigatorTests(unittest.TestCase):
    def test_fast_intents(self):
        self.assertEqual(navigator.fast_kind("Какие правила?"), "rules")
        self.assertEqual(navigator.fast_kind("как подать заявку"), "apply")
        self.assertIsNone(navigator.fast_kind("Как создать клан?"))

    def test_rate_limit(self):
        navigator._recent.clear()
        results = [navigator.allowed(1, now=1000 + i) for i in range(8)]
        self.assertEqual(results, [True] * navigator.LIMIT_PER_MINUTE + [False, False])

    def test_guide_states(self):
        self.assertIn("Подать заявку", build_guide("NO_APPLICATION", {})[0])
        _, markup = build_guide("PENDING", {})
        self.assertIsNone(markup)
        text, _ = build_guide("ACCEPTED", {"is_whitelisted": True, "minecraft_nickname": "<b>x"})
        self.assertIn("&lt;b&gt;x", text)  # nick is escaped


class StatusLookupTests(unittest.IsolatedAsyncioTestCase):
    async def test_status_is_loaded_only_for_guide_intents(self):
        calls = []
        original = ai_handler.bot_get_user_status

        async def fake_status(tg_id):
            calls.append(tg_id)
            return "PENDING"

        ai_handler.bot_get_user_status = fake_status
        try:
            self.assertEqual(await ai_handler._status_for_intent(42, None), "")
            self.assertEqual(await ai_handler._status_for_intent(42, "rules"), "")
            self.assertEqual(calls, [])
            self.assertEqual(await ai_handler._status_for_intent(42, "guide"), "PENDING")
            self.assertEqual(await ai_handler._status_for_intent(42, "apply"), "PENDING")
            self.assertEqual(calls, [42, 42])
        finally:
            ai_handler.bot_get_user_status = original


class AdminActionTests(unittest.IsolatedAsyncioTestCase):
    async def test_permission_is_checked_at_click_time(self):
        executed = []

        async def deny(callback, permission):
            return False

        async def approve(uid, admin_id):
            executed.append(uid)
            return Result({"success": True})

        admin_actions.require_callback_perm = deny
        admin_actions.bot_approve_application = approve
        await admin_actions.admin_action(Callback("adm:app:ok:11111111-1111-1111-1111-111111111111"))
        self.assertEqual(executed, [])  # denied: nothing executed

    async def test_destructive_action_needs_second_tap(self):
        executed = []

        async def allow(callback, permission):
            return True

        async def reject(uid, admin_id, reason):
            executed.append(uid)
            return Result({"success": True})

        class Message:
            html_text = "card"

            async def edit_reply_markup(self, reply_markup=None):
                pass

            async def edit_text(self, *a, **k):
                pass

        admin_actions.require_callback_perm = allow
        admin_actions.bot_reject_application = reject
        uid = "11111111-1111-1111-1111-111111111111"
        first = Callback(f"adm:app:no:{uid}")
        first.message = Message()
        await admin_actions.admin_action(first)
        self.assertEqual(executed, [])  # only asked for confirmation
        second = Callback(f"adm:app:no!:{uid}")
        second.message = Message()
        await admin_actions.admin_action(second)
        self.assertEqual(executed, [uid])


class CopilotToolTests(unittest.IsolatedAsyncioTestCase):
    async def test_tool_denied_without_permission(self):
        async def no(admin_id, permission):
            return Result(False)

        admin_tools.bot_check_admin_permission = no
        out = await admin_tools.execute("list_players", {}, admin_tools.Context(5))
        self.assertEqual(out, {"error": "no permission"})

    async def test_unknown_tool_and_propose_missing_row(self):
        async def yes(admin_id, permission):
            return Result(True)

        async def none(admin_id, limit=10):
            return [], None

        admin_tools.bot_check_admin_permission = yes
        admin_tools.pending_applications = none
        ctx = admin_tools.Context(5)
        self.assertEqual((await admin_tools.execute("drop_table", {}, ctx))["error"], "unknown tool")
        out = await admin_tools.execute("propose_application_action", {"application_id": "x", "action": "approve"}, ctx)
        self.assertIn("error", out)
        self.assertEqual(ctx.cards, [])


if __name__ == "__main__":
    unittest.main()
