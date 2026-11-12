"""Test stand: a member's journey played through the real bot logic against an in-memory fake database.

No Telegram, no Supabase, no Docker: every RPC goes to FakeDb, so the scenario runs in CI and shows
that the pieces work *together* (memory across a restart, reminders, market trust, unprompted talk, cards).
"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from db import rpc  # noqa: E402
from services import market_risk, reminders  # noqa: E402
from services.ai import ambient, member_tools, memory  # noqa: E402

UUID = "123e4567-e89b-12d3-a456-426614174000"


class FakeDb:
    def __init__(self):
        self.chat_log = []
        self.reminders = {}
        self.calls = []

    async def __call__(self, name, params, **_):
        self.calls.append(name)
        handler = getattr(self, f"rpc_{name}", None)
        if handler is None:
            return rpc.RPCResult(data=None, error=f"unfaked rpc {name}")
        return rpc.RPCResult(data=handler(params))

    def rpc_bot_ai_log_message(self, p):
        self.chat_log.append({"role": p["p_role"], "content": p["p_content"], "answer_id": p["p_answer_id"],
                              "rating": None, "ts": datetime.now(timezone.utc).timestamp(),
                              "tg": p["p_tg_id"], "chat": p["p_chat_id"]})

    def rpc_bot_ai_recent(self, p):
        return [r for r in self.chat_log if r["tg"] == p["p_tg_id"] and r["chat"] == p["p_chat_id"]][-p["p_limit"]:]

    def rpc_bot_ai_rate(self, p):
        for r in self.chat_log:
            if r["answer_id"] == p["p_answer_id"] and r["tg"] == p["p_tg_id"]:
                r["rating"] = p["p_rating"]
                return True
        return False

    def rpc_bot_create_reminder(self, p):
        rid = f"r{len(self.reminders) + 1}"
        self.reminders[rid] = {"id": rid, "text": p["p_text"], "at": p["p_at"], "owner": p["p_tg_id"]}
        return {"id": rid, "at": p["p_at"]}

    def rpc_bot_list_reminders(self, p):
        return [r for r in self.reminders.values() if r["owner"] == p["p_tg_id"]]

    def rpc_bot_cancel_reminder(self, p):
        return self.reminders.pop(p["p_id"], None) is not None

    def rpc_bot_get_market(self, p):
        return [{"id": UUID, "kind": "SELL", "title": "Алмазы", "price_text": "5", "minecraft_nickname": "Steve"}]


class MemberJourney(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.db = FakeDb()
        self._orig = rpc.call_rpc_async
        rpc.call_rpc_async = self.db
        memory.forget(1, 42)
        ambient._buffers.pop(1, None)

    def tearDown(self):
        rpc.call_rpc_async = self._orig

    async def test_memory_survives_restart_and_knows_the_like(self):
        answer_id = memory.new_answer_id()
        memory.remember(1, 42, "user", "привет, я Саша")
        memory.remember(1, 42, "assistant", "Привет, Саша!", answer_id=answer_id)
        await memory.persist(1, 42, "user", "привет, я Саша")
        await memory.persist(1, 42, "assistant", "Привет, Саша!", answer_id)
        await memory.rate(42, 1, answer_id, 1)             # the member liked the answer
        memory.forget(1, 42)                               # bot restarts: RAM is gone
        self.assertEqual(memory.history(1, 42), [])
        await memory.hydrate(1, 42)                        # next message: history comes back from the DB
        history = memory.history(1, 42)
        self.assertEqual([h["role"] for h in history], ["user", "assistant"])
        self.assertIn("👍", history[1]["content"])

    async def test_reminder_lifecycle(self):
        when, text = reminders.parse("через 2 часа проверить заявки")
        ok, message = await reminders.create(42, text, when)
        self.assertTrue(ok)
        self.assertIn("проверить заявки", message)
        listed = await reminders.listing(42)
        self.assertEqual(len(listed), 1)
        self.assertTrue(await reminders.cancel(42, listed[0]["id"]))
        self.assertEqual(await reminders.listing(42), [])

    async def test_reminder_via_ai_tool(self):
        result = await member_tools.reminders_tool("set_reminder", {"text": "ивент", "in_minutes": 30}, 42)
        self.assertTrue(result["ok"])
        self.assertEqual((await member_tools.reminders_tool("list_reminders", {}, 42))["reminders"][0]["text"], "ивент")

    async def test_unprompted_chat_invites_to_dm(self):
        ambient.observe(1, 10, 42, "Саша", "лол вчера на сервере было круто")
        ambient.observe(1, 11, 42, "Саша", "хочу подать заявку, как это сделать?")
        self.assertTrue(ambient.worth_considering("хочу подать заявку, как это сделать?"))

        async def fake_model(messages, **kw):
            self.assertIn("лол вчера", messages[1]["content"])      # the model sees the earlier unaddressed lines
            return {"content": '{"action":"invite","intent":"apply"}'}

        original = ambient.chat_with_fallback
        ambient.chat_with_fallback = fake_model
        try:
            decision = await ambient.decide(1, "Саша", "хочу подать заявку, как это сделать?")
        finally:
            ambient.chat_with_fallback = original
        self.assertEqual(decision, {"action": "invite", "intent": "apply"})
        url = ambient.invite_url("prisma_eco_bot", decision["intent"])
        self.assertEqual(ambient.intent_from_start(url.split("start=")[1])[0], "apply")

    async def test_market_search_shows_cards_with_actions(self):
        ctx = member_tools.Context(42, True, True)
        result = await member_tools.execute("search_market", {"query": "алмазы"}, ctx)
        self.assertEqual(result["listings"][0]["title"], "Алмазы")
        _, markup = ctx.cards[0]
        data = [b.callback_data for row in markup.inline_keyboard for b in row if b.callback_data]
        self.assertEqual(data, [f"cd:off:{UUID}", "cd:rep:Steve"])

    def test_market_anti_fraud_ranks_the_scammer_first(self):
        now = datetime.now(timezone.utc)
        rows = [
            {"id": "ok", "title": "Продам железо", "description": "стак", "seller_nickname": "Old",
             "seller_created_at": (now - timedelta(days=90)).isoformat(), "seller_listings_24h": 1},
            {"id": "bad", "title": "АЛМАЗНЫЙ НАБОР", "description": "предоплата, пиши t.me/x_scam",
             "seller_nickname": "New", "seller_created_at": (now - timedelta(hours=2)).isoformat(), "seller_listings_24h": 7},
        ]
        flagged = market_risk.score_listings(rows, now)
        self.assertEqual([f["id"] for f in flagged], ["bad"])
        self.assertEqual(flagged[0]["level"], "high")


if __name__ == "__main__":
    unittest.main()
