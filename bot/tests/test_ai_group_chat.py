import asyncio
import os
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from handlers import ai as ai_handler  # noqa: E402
from services.ai import ambient, member_tools  # noqa: E402


class Sent:
    message_id = 900


class FakeMessage:
    def __init__(self, text="что за бред"):
        self.text = text
        self.message_id = 50
        self.chat = SimpleNamespace(id=-1001, type="supergroup")
        self.from_user = SimpleNamespace(id=7, first_name="Назар")
        self.replies = []
        self.bot = SimpleNamespace(send_chat_action=mock.AsyncMock())

    async def reply(self, text, **kw):
        self.replies.append(text)
        return Sent()

    async def answer(self, text, **kw):
        self.replies.append(text)
        return Sent()


class GroupChatTests(unittest.TestCase):
    def setUp(self):
        ambient._buffers.pop(-1001, None)
        ambient._adult.clear()

    def test_transcript_has_authors_and_bot_lines_without_current_message(self):
        ambient.observe(-1001, 1, 5, "Саша", "это сервер вообще живой?")
        ambient.observe_bot(-1001, 2, "Да, онлайн 3 игрока")
        ambient.observe(-1001, 50, 7, "Назар", "Призма, что за бред")
        text = ambient.transcript(-1001, 14, exclude_id=50)
        self.assertEqual(text, "Саша: это сервер вообще живой?\nPRISMA_AI: Да, онлайн 3 игрока")

    def test_followup_without_name_while_in_conversation(self):
        ambient.observe(-1001, 1, 7, "Назар", "Призма", now=1000)
        ambient.observe_bot(-1001, 2, "Да?", now=1005, to_user=7)
        ambient.observe(-1001, 3, 7, "Назар", "ты гей", now=1010)
        self.assertTrue(ambient.in_conversation(-1001, 7, now=1011))
        self.assertFalse(ambient.in_conversation(-1001, 8, now=1011))   # someone else
        self.assertFalse(ambient.in_conversation(-1001, 7, now=1005 + ambient.FOLLOWUP_WINDOW + 1))  # too late
        ambient.observe(-1001, 4, 9, "Вова", "привет всем", now=1012)
        self.assertFalse(ambient.in_conversation(-1001, 7, now=1013))   # another person joined

    def test_adult_mode_toggle_and_env_default(self):
        self.assertFalse(ambient.adult(-1001))
        ambient.set_adult(-1001, 2)
        self.assertEqual(ambient.adult(-1001), 2)
        ambient.set_adult(-1001, 0)
        with mock.patch.dict(os.environ, {"AI_ADULT_CHATS": "-1001, -1002"}):
            ambient._adult.clear()
            self.assertTrue(ambient.adult(-1001))
            self.assertFalse(ambient.adult(-5))

    def test_answer_returns_true_so_no_fallback_error_follows(self):
        """Regression: a successful model answer used to return None and the code fallback then said «не получилось»."""
        message = FakeMessage()
        run = mock.AsyncMock(return_value=("Это про вчерашний спор о ценах.", []))
        with mock.patch.object(ai_handler, "run_member", run), \
                mock.patch.object(ai_handler, "bot_get_user_status", mock.AsyncMock(return_value="ACCEPTED")), \
                mock.patch.object(ai_handler.navigator, "allowed", return_value=True), \
                mock.patch.object(ai_handler.ai_memory_module, "hydrate", mock.AsyncMock()), \
                mock.patch.object(ai_handler.ai_memory_module, "persist", mock.AsyncMock()):
            ambient.observe(-1001, 1, 5, "Саша", "цены на рынке бред")
            ok = asyncio.run(ai_handler._ask_ai(message, "что за бред", False))
        self.assertTrue(ok)
        self.assertEqual(len(message.replies), 1)  # exactly one message, no «thinking» and no error
        kwargs = run.await_args.kwargs
        self.assertIn("Саша: цены на рынке бред", kwargs["chat_context"])
        self.assertEqual(kwargs["asker"], "Назар")
