import os
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from handlers import accounts as handler
from services import accounts


class CodeTests(unittest.TestCase):
    def setUp(self):
        accounts._codes.clear()
        accounts._alias_cache.clear()

    def test_code_is_single_use(self):
        code = accounts.new_code(10, now=0)
        self.assertEqual(accounts.take_code(code, now=1), 10)
        self.assertIsNone(accounts.take_code(code, now=2))

    def test_code_expires(self):
        code = accounts.new_code(10, now=0)
        self.assertIsNone(accounts.take_code(code, now=accounts.CODE_TTL + 1))

    def test_new_code_replaces_the_old_one(self):
        old = accounts.new_code(10, now=0)
        new = accounts.new_code(10, now=1)
        self.assertIsNone(accounts.take_code(old, now=2))
        self.assertEqual(accounts.take_code(new.lower(), now=2), 10)

    def test_unknown_code(self):
        self.assertIsNone(accounts.take_code("", now=0))
        self.assertIsNone(accounts.take_code("NOPE", now=0))


class ResolveTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        accounts._alias_cache.clear()

    async def test_resolves_and_caches_including_negatives(self):
        calls = []

        async def fake(tg):
            calls.append(tg)
            return SimpleNamespace(error=None, data=77 if tg == 5 else None)

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            self.assertEqual(await accounts.primary_for(5, now=0), 77)
            self.assertEqual(await accounts.primary_for(5, now=1), 77)
            self.assertIsNone(await accounts.primary_for(6, now=0))
            self.assertIsNone(await accounts.primary_for(6, now=1))
        self.assertEqual(calls, [5, 6])

    async def test_rpc_failure_means_no_alias(self):
        async def boom(tg):
            raise RuntimeError("down")

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", boom):
            self.assertIsNone(await accounts.primary_for(5, now=0))


class MiddlewareTests(unittest.IsolatedAsyncioTestCase):
    async def test_private_message_from_alias_gets_the_primary_identity(self):
        from aiogram import types

        seen = {}

        async def inner(event, data):
            seen["id"] = event.from_user.id
            seen["chat"] = event.chat.id
            seen["data"] = data["event_from_user"].id

        message = types.Message(message_id=1, date=0, chat=types.Chat(id=500, type="private"),
                                from_user=types.User(id=500, is_bot=False, first_name="B", username="second"), text="/me")

        async def fake_primary(tg):
            return 77

        with mock.patch.object(accounts, "primary_for", fake_primary):
            await handler.TelegramAliasMiddleware()(inner, message, {})
        self.assertEqual(seen, {"id": 77, "chat": 500, "data": 77})

    async def test_group_messages_are_left_alone(self):
        from aiogram import types

        seen = {}

        async def inner(event, data):
            seen["id"] = event.from_user.id

        message = types.Message(message_id=1, date=0, chat=types.Chat(id=-100, type="supergroup"),
                                from_user=types.User(id=500, is_bot=False, first_name="B"), text="hi")

        async def fake_primary(tg):
            raise AssertionError("must not look up aliases in groups")

        with mock.patch.object(accounts, "primary_for", fake_primary):
            await handler.TelegramAliasMiddleware()(inner, message, {})
        self.assertEqual(seen["id"], 500)


if __name__ == "__main__":
    unittest.main()
