import os
import sys
import time
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


class NewCodeEdgeCases(unittest.TestCase):
    def setUp(self):
        accounts._codes.clear()
        accounts._alias_cache.clear()

    def test_new_code_returns_8_char_uppercase(self):
        code = accounts.new_code(10, now=0)
        self.assertEqual(len(code), 8)
        self.assertTrue(code.isupper())
        self.assertTrue(all(c in accounts._ALPHABET for c in code))

    def test_new_code_removes_expired_codes(self):
        accounts.new_code(10, now=0)
        accounts.new_code(20, now=100)
        # At now=700, first code expired (TTL=600), second still valid
        code = accounts.new_code(30, now=700)
        self.assertEqual(len(accounts._codes), 2)  # expired removed, new added

    def test_new_code_only_one_live_per_primary(self):
        code1 = accounts.new_code(10, now=0)
        code2 = accounts.new_code(10, now=1)
        self.assertNotEqual(code1, code2)
        self.assertEqual(len(accounts._codes), 1)
        self.assertEqual(accounts.take_code(code2, now=2), 10)
        self.assertIsNone(accounts.take_code(code1, now=2))

    def test_new_code_different_primaries_can_have_codes(self):
        code1 = accounts.new_code(10, now=0)
        code2 = accounts.new_code(20, now=0)
        self.assertNotEqual(code1, code2)
        self.assertEqual(len(accounts._codes), 2)
        self.assertEqual(accounts.take_code(code1, now=1), 10)
        self.assertEqual(accounts.take_code(code2, now=1), 20)


class TakeCodeEdgeCases(unittest.TestCase):
    def setUp(self):
        accounts._codes.clear()
        accounts._alias_cache.clear()

    def test_take_code_case_insensitive(self):
        code = accounts.new_code(10, now=0)
        self.assertEqual(accounts.take_code(code.lower(), now=1), 10)
        self.assertIsNone(accounts.take_code(code.upper(), now=2))

    def test_take_code_strips_whitespace(self):
        code = accounts.new_code(10, now=0)
        self.assertEqual(accounts.take_code(f"  {code}  ", now=1), 10)

    def test_take_code_empty_string_returns_none(self):
        self.assertIsNone(accounts.take_code("", now=0))
        self.assertIsNone(accounts.take_code("   ", now=0))

    def test_take_code_expired_returns_none_and_removes(self):
        code = accounts.new_code(10, now=0)
        self.assertIsNone(accounts.take_code(code, now=accounts.CODE_TTL + 1))
        self.assertNotIn(code, accounts._codes)


class PrimaryForEdgeCases(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        accounts._alias_cache.clear()

    async def test_primary_for_cache_hit(self):
        accounts._alias_cache[5] = (77, time.time() + 100)
        with mock.patch.object(accounts, "bot_telegram_alias_resolve") as m:
            result = await accounts.primary_for(5, now=time.time())
            self.assertEqual(result, 77)
            m.assert_not_called()

    async def test_primary_for_cache_expired_calls_rpc(self):
        accounts._alias_cache[5] = (77, time.time() - 100)
        calls = []

        async def fake(tg):
            calls.append(tg)
            return SimpleNamespace(error=None, data=88)

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=time.time())
            self.assertEqual(result, 88)
            self.assertEqual(calls, [5])

    async def test_primary_for_rpc_returns_error(self):
        async def fake(tg):
            return SimpleNamespace(error="some error", data=None)

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=0)
            self.assertIsNone(result)

    async def test_primary_for_rpc_returns_empty_data(self):
        async def fake(tg):
            return SimpleNamespace(error=None, data="")

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=0)
            self.assertIsNone(result)

    async def test_primary_for_rpc_returns_none_data(self):
        async def fake(tg):
            return SimpleNamespace(error=None, data=None)

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=0)
            self.assertIsNone(result)

    async def test_primary_for_rpc_returns_invalid_int(self):
        async def fake(tg):
            return SimpleNamespace(error=None, data="not-a-number")

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=0)
            self.assertIsNone(result)

    async def test_primary_for_rpc_returns_float_string(self):
        async def fake(tg):
            return SimpleNamespace(error=None, data="77.5")

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", fake):
            result = await accounts.primary_for(5, now=0)
            self.assertIsNone(result)

    async def test_primary_for_rpc_exception_logged(self):
        async def boom(tg):
            raise RuntimeError("down")

        with mock.patch.object(accounts, "bot_telegram_alias_resolve", boom):
            with self.assertLogs(logger="services.accounts", level="ERROR"):
                result = await accounts.primary_for(5, now=0)
                self.assertIsNone(result)


class ForgetTests(unittest.TestCase):
    def setUp(self):
        accounts._codes.clear()
        accounts._alias_cache.clear()

    def test_forget_clears_all_cache(self):
        accounts._alias_cache[1] = (10, time.time() + 100)
        accounts._alias_cache[2] = (20, time.time() + 100)
        accounts.forget()
        self.assertEqual(len(accounts._alias_cache), 0)

    def test_forget_clears_specific_tg_id(self):
        accounts._alias_cache[1] = (10, time.time() + 100)
        accounts._alias_cache[2] = (20, time.time() + 100)
        accounts.forget(1)
        self.assertNotIn(1, accounts._alias_cache)
        self.assertIn(2, accounts._alias_cache)


if __name__ == "__main__":
    unittest.main()
