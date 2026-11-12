import asyncio
import os
import re
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.ai import ambient, client, member_tools, memory  # noqa: E402
from utils import commands  # noqa: E402


class NameAddressingTests(unittest.TestCase):
    def test_addressed_by_name(self):
        for text in ("призма ты тут?", "Призма, помоги", "ти тут, призма?", "Прізма що там", "prisma_ai привет"):
            self.assertTrue(ambient.addressed_by_name(text), text)

    def test_talking_about_prisma_is_not_addressing(self):
        for text in ("зайди на призму вечером", "в призме классно играть", "сервер призма работает?"):
            self.assertFalse(ambient.addressed_by_name(text), text)

    def test_strip_name(self):
        self.assertEqual(ambient.strip_name("Призма, ты тут?"), "ты тут?")
        self.assertEqual(ambient.strip_name("помоги, призма"), "помоги")

    def test_chat_context_remembers_unaddressed_lines(self):
        ambient._buffers.pop(77, None)
        ambient.observe(77, 1, 5, "Саша", "я вчера продал алмазы")
        ambient.observe(77, 2, 6, "Вова", "а я хочу купить")
        ctx = ambient.context_lines(77, limit=15)
        self.assertIn("Саша: я вчера продал алмазы", ctx)
        self.assertEqual(len(ctx.splitlines()), 2)


class SmalltalkTests(unittest.TestCase):
    def test_smalltalk_skips_tools(self):
        for text in ("ты тут?", "привет", "спасибо", "ау"):
            self.assertTrue(member_tools._is_smalltalk(text), text)
        for text in ("как подать заявку?", "сколько онлайн", "хочу продать алмазы", "напомни через час"):
            self.assertFalse(member_tools._is_smalltalk(text), text)


class CommandMenuTests(unittest.TestCase):
    def test_group_menu_is_short_and_valid(self):
        for lst in (commands.GROUP_COMMANDS, commands.GROUP_ADMIN_COMMANDS):
            names = [c.command for c in lst]
            self.assertEqual(len(names), len(set(names)))
            for c in lst:
                self.assertRegex(c.command, r"^[a-z0-9_]{1,32}$")
                self.assertLessEqual(len(c.description), 256)
        group = {c.command for c in commands.GROUP_COMMANDS}
        self.assertLessEqual(len(group), 9)
        self.assertIn("ai", group)
        self.assertTrue(group.isdisjoint({"marriage", "relationship", "who", "inactive", "start", "market"}))
        admin_only = {c.command for c in commands.GROUP_ADMIN_COMMANDS} - group
        self.assertTrue({"warn", "mute", "ban", "ai_chat"} <= admin_only)


class ReactionBindingTests(unittest.TestCase):
    def test_bind_and_lookup(self):
        memory.bind(1, 500, 42, "abc")
        self.assertEqual(memory.owner_of(1, 500), (42, "abc"))
        self.assertIsNone(memory.owner_of(1, 501))


class FallbackBreakerTests(unittest.IsolatedAsyncioTestCase):
    async def test_primary_failure_opens_breaker(self):
        calls = []

        async def fake_chat(messages, *, role="user", model=None, **kw):
            calls.append((model, kw.get("timeout")))
            if model is None or model == client.model_for(role):
                raise client.AIError("TimeoutError")
            return {"content": "ok"}

        original = client.chat
        client.chat = fake_chat
        client._primary_down_until.clear()
        try:
            self.assertEqual((await client.chat_with_fallback([], role="user", timeout=45))["content"], "ok")
            self.assertEqual(calls[0][1], client.PRIMARY_TIMEOUT)      # short slice for the primary
            before = len(calls)
            await client.chat_with_fallback([], role="user", timeout=45)
            self.assertEqual(len(calls) - before, 1)                    # breaker open: fallback only
        finally:
            client.chat = original
            client._primary_down_until.clear()


if __name__ == "__main__":
    unittest.main()
