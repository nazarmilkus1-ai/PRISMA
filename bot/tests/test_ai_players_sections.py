"""Run: cd bot && python -m unittest discover -s tests -v   (no network, no database)."""
import asyncio
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

from handlers import ai as ai_handler  # noqa: E402
from keyboards.inline import main_menu_approved  # noqa: E402
from services.ai import admin_tools, client, sections, wiki  # noqa: E402
from services.ai.players import apply_player_filter, parse_player_filter  # noqa: E402

ROWS = [
    {"display_name": "AL.O", "username": "Alominq", "nickname": ".alominq"},
    {"display_name": "Nastia", "username": "Na0561", "nickname": ".Nast11k211"},
    {"display_name": "Zero", "username": None, "nickname": "Zerohero19"},
    {"display_name": "xN4ZARx", "username": "xN4ZARx", "nickname": "xN4ZARx"},
    {"display_name": "Bob", "username": "Bobminec", "nickname": "wsert3n1h"},
]


class Result:
    def __init__(self, data=None, error=None):
        self.data, self.error = data, error


class FakeMessage:
    def __init__(self):
        self.sent = []
        self.from_user = types.SimpleNamespace(id=7, full_name="Admin")

    async def answer(self, text, **kwargs):
        self.sent.append((text, kwargs))
        return self


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


def callbacks(markup):
    return [b.callback_data for row in markup.inline_keyboard for b in row]


class PlayerFilterTests(unittest.TestCase):
    def test_bedrock_filter_uses_dot_prefix(self):
        flt = parse_player_filter("список игроков бедрок")
        self.assertEqual(flt.platform, "bedrock")
        self.assertFalse(flt.nicks_only)
        rows = apply_player_filter(ROWS, flt)
        self.assertEqual([r["nickname"] for r in rows], [".alominq", ".Nast11k211"])

    def test_nicks_only_for_nick_requests(self):
        flt = parse_player_filter("список ников которые играют на бедрок")
        self.assertEqual(flt.platform, "bedrock")
        self.assertTrue(flt.nicks_only)
        self.assertFalse(parse_player_filter("список ников и их юзы").nicks_only)

    def test_java_and_telegram_filters(self):
        java = apply_player_filter(ROWS, parse_player_filter("игроки java"))
        self.assertEqual([r["nickname"] for r in java], ["Zerohero19", "xN4ZARx", "wsert3n1h"])
        no_tg = apply_player_filter(ROWS, parse_player_filter("список игроков без юзернейма"))
        self.assertEqual([r["display_name"] for r in no_tg], ["Zero"])

    def test_unfiltered_request_returns_everyone(self):
        flt = parse_player_filter("список игроков и их юзы")
        self.assertFalse(flt.is_filtered)
        self.assertEqual(len(apply_player_filter(ROWS, flt)), len(ROWS))

    def test_unsupported_qualifier_is_flagged(self):
        self.assertTrue(parse_player_filter("список игроков онлайн в клане").unsupported)


class CopilotReportTests(unittest.TestCase):
    def setUp(self):
        self._saved = (ai_handler.bot_list_current_participants, ai_handler._has, ai_handler.is_configured)

        async def participants():
            return Result(ROWS)

        async def allowed(admin_id, permission):
            return True

        ai_handler.bot_list_current_participants = participants
        ai_handler._has = allowed
        ai_handler.is_configured = lambda role="user": False

    def tearDown(self):
        ai_handler.bot_list_current_participants, ai_handler._has, ai_handler.is_configured = self._saved

    def test_bedrock_request_lists_only_bedrock_without_model(self):
        message = FakeMessage()
        run(ai_handler._copilot(message, "список игроков бедрок"))
        text = message.sent[-1][0]
        self.assertIn(".alominq", text)
        self.assertIn(".Nast11k211", text)
        self.assertNotIn("Zerohero19", text)
        self.assertIn("(2)", text)

    def test_nick_only_request_prints_nicks_only(self):
        message = FakeMessage()
        run(ai_handler._copilot(message, "список ников которые играют на бедрок"))
        text = message.sent[-1][0]
        self.assertIn("<code>.alominq</code>", text)
        self.assertNotIn("Alominq", text)  # no @username column

    def test_copilot_tool_filters_by_platform(self):
        ctx = admin_tools.Context(7)
        saved = admin_tools.bot_list_current_participants, admin_tools._allowed

        async def allowed(admin_id, permission):
            return True

        async def participants():
            return Result(ROWS)

        admin_tools.bot_list_current_participants, admin_tools._allowed = participants, allowed
        try:
            out = run(admin_tools.execute("list_players", {"platform": "bedrock"}, ctx))
        finally:
            admin_tools.bot_list_current_participants, admin_tools._allowed = saved
        self.assertEqual(out["total"], 2)


class SectionTests(unittest.TestCase):
    def test_member_gets_live_section_buttons(self):
        text, markup = sections.build_answer("кто сейчас онлайн", "ACCEPTED")
        self.assertIn("player:server", callbacks(markup))

    def test_guest_gets_guest_variant_or_lock(self):
        _, markup = sections.build_answer("какой айпи сервера", "NO_APPLICATION")
        self.assertIn("about_server", callbacks(markup))
        text, markup = sections.build_answer("как вступить в клан", "NO_APPLICATION")
        self.assertIn("после одобрения", text)
        self.assertIn("apply", callbacks(markup))

    def test_unknown_question_has_no_section(self):
        self.assertIsNone(sections.build_answer("расскажи анекдот", "ACCEPTED"))

    def test_every_callback_exists_in_a_real_menu(self):
        known = {"player:server", "player:stats", "player:achievements", "player:top", "player:events", "clans",
                 "market", "news", "polls", "reports", "support", "menu:link", "player:mc_auth",
                 "player:minecraft_commands", "player:notifications", "profile", "menu:help", "about_server",
                 "apply", "guide", "about_prisma"}
        for section in sections.SECTIONS:
            for cb in (section.member_cb, section.guest_cb):
                if cb:
                    self.assertIn(cb, known, section.key)


class AnswerQualityTests(unittest.TestCase):
    def test_what_is_prisma_is_answered_by_code(self):
        text, markup = sections.build_answer("Что такое призма", "ACCEPTED")
        self.assertIn("Minecraft", text)
        self.assertIn("about_prisma", callbacks(markup))

    def test_wiki_context_is_trimmed_and_cleaned(self):
        pages = [{"title": "Правила", "content": "<p>**Не** читерить</p>\n\n# Заголовок " + "x" * 2000},
                 {"title": "Пусто", "content": ""}, "garbage"]
        text = wiki.format_pages(pages, max_chars=1000)
        self.assertIn("[Правила] Не читерить Заголовок", text)
        self.assertNotIn("<p>", text)
        self.assertLessEqual(len(text), 1000)

    def test_empty_wiki_gives_empty_context(self):
        self.assertEqual(wiki.format_pages([]), "")

    def test_reasoning_only_reply_is_reported_not_returned_empty(self):
        saved = client.aiohttp.ClientSession

        class Resp:
            status = 200

            async def json(self, content_type=None):
                return {"choices": [{"finish_reason": "length", "message": {"content": "", "reasoning_content": "думаю"}}]}

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

        class Session:
            def __init__(self, *a, **k):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *a):
                return False

            def post(self, *a, **k):
                return Resp()

        client.aiohttp.ClientSession = Session
        os.environ["AI_API_KEY_USER"] = "test-key"
        try:
            with self.assertRaises(client.AIError) as ctx:
                run(client.chat([{"role": "user", "content": "hi"}]))
        finally:
            client.aiohttp.ClientSession = saved
            os.environ.pop("AI_API_KEY_USER", None)
        self.assertIn("token budget", str(ctx.exception))


class MenuTests(unittest.TestCase):
    def test_approved_member_menu_has_ask_button(self):
        self.assertIn("ask", callbacks(main_menu_approved()))

    def test_free_text_router_is_registered_handler(self):
        self.assertTrue(ai_handler.free_router.message.handlers)


if __name__ == "__main__":
    unittest.main()
