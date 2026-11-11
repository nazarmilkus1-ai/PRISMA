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

from services.ai import links, member_tools as mt, memory  # noqa: E402


def run(coro):
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def ok(data=None):
    return types.SimpleNamespace(data=data, error=None)


class CalcTests(unittest.TestCase):
    def test_arithmetic(self):
        self.assertEqual(mt.safe_calc("64*27"), 1728)
        self.assertEqual(mt.safe_calc("(10+5)/3"), 5)
        self.assertEqual(mt.safe_calc("2^10"), 1024)
        self.assertAlmostEqual(mt.safe_calc("1,5*2"), 3.0)

    def test_rejects_code_and_huge_powers(self):
        for bad in ("__import__('os').system('x')", "open('f')", "9**99", "[1]*5", "a+1"):
            with self.assertRaises((ValueError, SyntaxError, TypeError)):
                mt.safe_calc(bad)


class MemoryTests(unittest.TestCase):
    def test_window_and_ttl(self):
        memory.forget(1, 2)
        for i in range(12):
            memory.remember(1, 2, "user", f"m{i}", now=100.0 + i)
        hist = memory.history(1, 2, now=120.0)
        self.assertEqual(len(hist), memory.MAX_MESSAGES)
        self.assertEqual(hist[-1]["content"], "m11")
        self.assertEqual(memory.history(1, 2, now=100.0 + memory.TTL_SECONDS + 500), [])

    def test_isolated_per_user(self):
        memory.forget(5, 1)
        memory.forget(5, 2)
        memory.remember(5, 1, "user", "secret", now=1.0)
        self.assertEqual(memory.history(5, 2, now=2.0), [])


class LinkTests(unittest.TestCase):
    def test_fixed_site_paths_only(self):
        buttons = links.link_buttons("где рынок и правила?", "")
        urls = [b.url for b in buttons]
        self.assertTrue(all(u.startswith("http") for u in urls))
        self.assertTrue(any(u.endswith("/market") for u in urls))
        self.assertTrue(any(u.endswith("/rules") for u in urls))
        self.assertLessEqual(len(links.link_buttons("рынок правила карта клан ивент", "")), 3)


class ToolTests(unittest.TestCase):
    def ctx(self, private=True, accepted=True):
        return mt.Context(7, private, accepted)

    def test_personal_tools_blocked_in_groups(self):
        for name in ("my_account", "draft_market_listing", "draft_support_request"):
            self.assertIn("error", run(mt.execute(name, {"title": "abc", "kind": "SELL", "message": "hello world"}, self.ctx(private=False))))

    def test_market_draft_needs_accepted_member(self):
        self.assertIn("error", run(mt.execute("draft_market_listing", {"kind": "SELL", "title": "Алмазы"}, self.ctx(accepted=False))))

    def test_market_draft_makes_card_and_is_one_shot_owner_only(self):
        ctx = self.ctx()
        result = run(mt.execute("draft_market_listing", {"kind": "SELL", "title": "Алмазы x64", "price": "10 эм", "days": 7}, ctx))
        self.assertIn("ok", result)
        data = ctx.cards[0][1].inline_keyboard[0][0].callback_data
        self.assertTrue(data.startswith("aim:mk:ok:"))
        draft_id = data.split(":")[3]
        self.assertIsNone(mt.take_draft(draft_id, 999))          # someone else
        self.assertIsNotNone(mt.take_draft(draft_id, 7))          # owner, once
        self.assertIsNone(mt.take_draft(draft_id, 7))             # not twice

    def test_bad_kind_rejected(self):
        self.assertIn("error", run(mt.execute("draft_market_listing", {"kind": "HACK", "title": "abc"}, self.ctx())))

    def test_publish_market_calls_rpc(self):
        payload = {"kind": "SELL", "title": "t", "description": None, "price": "1", "terms": None, "days": 0}
        with mock.patch.object(mt, "bot_create_market_listing", mock.AsyncMock(return_value=ok({}))) as rpc:
            done, text = run(mt.publish("mk", payload, 7))
        self.assertTrue(done)
        self.assertEqual(rpc.await_args.args[0], 7)
        self.assertIsNone(rpc.await_args.args[-1])

    def test_offer_draft_needs_real_listing_id_and_price(self):
        self.assertIn("error", run(mt.execute("draft_market_offer", {"listing_id": "nope", "price": "5"}, self.ctx())))
        ctx = self.ctx()
        lid = "123e4567-e89b-12d3-a456-426614174000"
        self.assertIn("ok", run(mt.execute("draft_market_offer", {"listing_id": lid, "price": "5 алмазов"}, ctx)))
        self.assertTrue(ctx.cards[0][1].inline_keyboard[0][0].callback_data.startswith("aim:of:ok:"))

    def test_offer_publish_calls_rpc(self):
        with mock.patch.object(mt, "bot_create_market_offer", mock.AsyncMock(return_value=ok({}))) as rpc:
            done, _ = run(mt.publish("of", {"listing_id": "x", "price": "5", "note": None}, 7))
        self.assertTrue(done)
        self.assertEqual(rpc.await_args.args[:3], (7, "x", "5"))

    def test_login_hints(self):
        hints = mt._login_hints("ACCEPTED", {"minecraft_nick": "Nick", "is_whitelisted": False}, {"platform": "JAVA", "configured": False})
        text = " ".join(hints)
        self.assertIn("whitelist", text)
        self.assertIn("Java Auth", text)
        self.assertIn("Заявка не подана", " ".join(mt._login_hints("NO_APPLICATION", {}, {})))



class RoutingTests(unittest.TestCase):
    """With a model configured, nothing is answered by canned code first."""

    def test_model_first_and_code_only_as_fallback(self):
        from handlers import ai as handler

        calls = []
        message = types.SimpleNamespace(from_user=types.SimpleNamespace(id=7), chat=types.SimpleNamespace(id=7))

        async def fake_ask(msg, question, private):
            calls.append(("ai", question))
            return True

        async def fake_code(msg, question, private):
            calls.append(("code", question))

        with mock.patch.object(handler, "is_configured", return_value=True), \
             mock.patch.object(handler, "_ask_ai", fake_ask), mock.patch.object(handler, "_answer_by_code", fake_code):
            run(handler._answer(message, "покажи правила", True))
            run(handler._answer(message, "", True))
        self.assertEqual(calls, [("ai", "покажи правила"), ("ai", "Привет")])

        calls.clear()

        async def failing_ask(msg, question, private):
            return False

        with mock.patch.object(handler, "is_configured", return_value=True), \
             mock.patch.object(handler, "_ask_ai", failing_ask), mock.patch.object(handler, "_answer_by_code", fake_code):
            run(handler._answer(message, "что такое призма", True))
        self.assertEqual(calls, [("code", "что такое призма")])

        calls.clear()
        with mock.patch.object(handler, "is_configured", return_value=False), mock.patch.object(handler, "_answer_by_code", fake_code):
            run(handler._answer(message, "правила", True))
        self.assertEqual(calls, [("code", "правила")])


if __name__ == "__main__":
    unittest.main()
