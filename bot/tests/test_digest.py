import os
import sys
import unittest
from unittest import mock
from datetime import datetime
from zoneinfo import ZoneInfo

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
os.environ.setdefault("MODERATION_GROUP_ID", "-100123")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import digest  # noqa: E402


class DigestGatherTests(unittest.TestCase):
    def test_gather_returns_dict(self):
        """gather должна возвращать словарь с фактами."""
        # gather делает реальные вызовы к БД, поэтому мокаем
        with mock.patch('services.digest.live._online', return_value="Сервер: RUNNING · онлайн 5/20"), \
             mock.patch('services.digest.bot_chat_top') as mock_top, \
             mock.patch('services.digest.bot_chat_top_total') as mock_total, \
             mock.patch('services.digest.bot_list_events') as mock_events:
            
            mock_top.return_value.error = False
            mock_top.return_value.data = [
                {"source_display_name": "Игрок1", "messages": 30},
                {"source_display_name": "Игрок2", "messages": 15}
            ]
            mock_total.return_value.error = False
            mock_total.return_value.data = 100
            mock_events.return_value.error = False
            mock_events.return_value.data = [
                {"title": "Ивент 1", "starts_at": "2026-12-01 18:00"}
            ]
            
            import asyncio
            facts = asyncio.run(digest.gather(-1001))
            
            self.assertIsInstance(facts, dict)
            self.assertIn("online", facts)
            self.assertIn("top", facts)
            self.assertIn("messages_today", facts)
            self.assertIn("events", facts)
            self.assertEqual(facts["messages_today"], 100)
            self.assertEqual(len(facts["top"]), 2)
            self.assertEqual(len(facts["events"]), 1)

    def test_gather_handles_errors_gracefully(self):
        """gather не должна падать, если один из источников вернул ошибку."""
        with mock.patch('services.digest.live._online', side_effect=Exception("fail")), \
             mock.patch('services.digest.bot_chat_top') as mock_top, \
             mock.patch('services.digest.bot_chat_top_total') as mock_total, \
             mock.patch('services.digest.bot_list_events') as mock_events:
            
            mock_top.return_value.error = True
            mock_total.return_value.error = True
            mock_events.return_value.error = True
            
            import asyncio
            facts = asyncio.run(digest.gather(-1001))
            
            self.assertIsInstance(facts, dict)
            # Все поля могут отсутствовать или быть пустыми
            self.assertEqual(facts, {})


class DigestTemplateTests(unittest.TestCase):
    def test_template_includes_all_facts(self):
        """template должна включать все переданные факты."""
        facts = {
            "online": "Сервер: RUNNING · онлайн 3/20",
            "top": [{"name": "Саша", "messages": 40}, {"name": "Вова", "messages": 12}],
            "messages_today": 120,
            "events": [{"title": "Битва кланов", "starts_at": "2026-11-14 18:00"}]
        }
        text = digest.template(facts)
        
        self.assertIn("Итоги дня в PRISMA", text)
        self.assertIn("онлайн 3/20", text)
        self.assertIn("Саша (40)", text)
        self.assertIn("Вова (12)", text)
        self.assertIn("120", text)
        self.assertIn("Битва кланов", text)
        self.assertIn("18:00", text)
        self.assertIn("Хорошего вечера", text)
        self.assertIn("PRISMA_AI", text)

    def test_template_with_minimal_facts(self):
        """template должна работать только с онлайн."""
        facts = {"online": "Сервер: RUNNING · онлайн 1/20"}
        text = digest.template(facts)
        
        self.assertIn("Итоги дня в PRISMA", text)
        self.assertIn("онлайн 1/20", text)
        self.assertIn("Хорошего вечера", text)

    def test_template_with_empty_facts(self):
        """template должна работать с пустым словарём."""
        facts = {}
        text = digest.template(facts)
        
        self.assertIn("Итоги дня в PRISMA", text)
        self.assertIn("Хорошего вечера", text)
        # Нет сообщений, топа, ивентов
        self.assertNotIn("Сообщений в чате", text)
        self.assertNotIn("Самые активные", text)
        self.assertNotIn("Ближайшие ивенты", text)

    def test_template_with_zero_messages(self):
        """template должна показывать 0 сообщений."""
        facts = {"messages_today": 0}
        text = digest.template(facts)
        
        self.assertIn("0", text)
        self.assertIn("Сообщений в чате за сутки: 0", text)


class DigestHasNewsTests(unittest.TestCase):
    def test_has_news_with_messages(self):
        """has_news должна возвращать True, если есть сообщения."""
        self.assertTrue(digest.has_news({"messages_today": 10}))
        self.assertTrue(digest.has_news({"messages_today": 1}))

    def test_has_news_with_events(self):
        """has_news должна возвращать True, если есть ивенты."""
        self.assertTrue(digest.has_news({"events": [{"title": "Ивент"}]}))

    def test_has_news_false_when_empty(self):
        """has_news должна возвращать False для пустого дня."""
        self.assertFalse(digest.has_news({}))
        self.assertFalse(digest.has_news({"online": "x", "messages_today": 0}))
        self.assertFalse(digest.has_news({"messages_today": 0, "events": []}))


class DigestBuildTests(unittest.IsolatedAsyncioTestCase):
    async def test_build_uses_template_when_ai_disabled(self):
        """build должна использовать шаблон, когда AI отключён."""
        facts = {"messages_today": 50, "online": "Сервер: RUNNING · онлайн 2/20"}
        
        with mock.patch('services.digest.is_configured', return_value=False):
            text = await digest.build(-1001, facts)
        
        self.assertIn("50", text)
        self.assertIn("Итоги дня в PRISMA", text)

    async def test_build_uses_model_when_available(self):
        """build должна использовать модель, когда она доступна."""
        facts = {"messages_today": 50}
        
        async def ok_model(messages, **kw):
            return {"content": "📰 Итоги дня в PRISMA\nСегодня 50 сообщений\nХорошего вечера!"}
        
        with mock.patch('services.digest.is_configured', return_value=True), \
             mock.patch('services.digest.chat_with_fallback', ok_model), \
             mock.patch('services.digest.ambient.adult', return_value=False):
            text = await digest.build(-1001, facts)
        
        self.assertIn("50 сообщений", text)
        self.assertIn("Итоги дня в PRISMA", text)

    async def test_build_falls_back_to_template_on_ai_error(self):
        """build должна падать на шаблон при ошибке AI."""
        facts = {"messages_today": 50, "events": [{"title": "Тест ивент", "starts_at": "2026-12-01 18:00"}]}
        
        async def broken_model(messages, **kw):
            raise digest.AIError("model down")
        
        with mock.patch('services.digest.is_configured', return_value=True), \
             mock.patch('services.digest.chat_with_fallback', broken_model), \
             mock.patch('services.digest.ambient.adult', return_value=False):
            text = await digest.build(-1001, facts)
        
        # Должен использоваться шаблон
        self.assertIn("Тест ивент", text)
        self.assertIn("Итоги дня в PRISMA", text)


class DigestEnabledTests(unittest.TestCase):
    def test_globally_enabled(self):
        """globally_enabled должна читать переменную окружения."""
        with mock.patch.dict(os.environ, {"AI_DIGEST": "1"}):
            self.assertTrue(digest.globally_enabled())
        with mock.patch.dict(os.environ, {"AI_DIGEST": "0"}):
            self.assertFalse(digest.globally_enabled())
        with mock.patch.dict(os.environ, {"AI_DIGEST": "false"}):
            self.assertFalse(digest.globally_enabled())
        with mock.patch.dict(os.environ, {"AI_DIGEST": "off"}):
            self.assertFalse(digest.globally_enabled())

    def test_enabled_per_chat(self):
        """enabled должна учитывать настройку чата."""
        digest._enabled.clear()
        with mock.patch.dict(os.environ, {"AI_DIGEST": "1"}):
            self.assertTrue(digest.enabled(-1))
            digest.set_enabled(-1, False)
            self.assertFalse(digest.enabled(-1))
            digest.set_enabled(-1, True)
            self.assertTrue(digest.enabled(-1))

    def test_manual_cooldown(self):
        """manual_allowed должна соблюдать кулдаун."""
        digest._last_manual.clear()
        self.assertTrue(digest.manual_allowed(-5, now=1000))
        self.assertFalse(digest.manual_allowed(-5, now=1100))
        self.assertTrue(digest.manual_allowed(-5, now=1000 + digest.COOLDOWN + 1))


class DigestFmtTests(unittest.TestCase):
    def test_fmt_datetime(self):
        """fmt должна форматировать datetime."""
        when = datetime(2026, 12, 25, 14, 30, tzinfo=ZoneInfo("Europe/Kyiv"))
        result = digest.fmt(when)
        self.assertIn("25.12", result)
        self.assertIn("14:30", result)

    def test_fmt_string(self):
        """fmt должна парсить ISO строку."""
        result = digest.fmt("2026-12-25T14:30:00+00:00")
        self.assertIn("25.12", result)
        # UTC+2 = 16:30
        self.assertIn("16:30", result)

    def test_fmt_none(self):
        """fmt должна возвращать 00.00 для None."""
        self.assertEqual(digest.fmt(None), "00.00")

    def test_fmt_empty_string(self):
        """fmt должна возвращать 00.00 для пустой строки."""
        self.assertEqual(digest.fmt(""), "00.00")


if __name__ == "__main__":
    unittest.main(verbosity=2)
