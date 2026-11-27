import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import digest


class DigestTemplateTests(unittest.TestCase):
    def test_template_no_facts(self):
        """Шаблон работает, когда нет никаких фактов."""
        result = digest.template({})
        self.assertIn("📰 Итоги дня в PRISMA", result)
        self.assertIn("Хорошего вечера!", result)

    def test_template_with_online(self):
        """Шаблон включает онлайн-статус."""
        result = digest.template({"online": "🟢 5 игроков онлайн"})
        self.assertIn("🟢 5 игроков онлайн", result)

    def test_template_with_messages(self):
        """Шаблон показывает количество сообщений."""
        result = digest.template({"messages_today": 42})
        self.assertIn("💬 Сообщений в чате за сутки: 42", result)

    def test_template_with_top(self):
        """Шаблон показывает топ активных игроков."""
        result = digest.template({"top": [{"name": "Player1", "messages": 100}, {"name": "Player2", "messages": 50}]})
        self.assertIn("🏆 Самые активные:", result)
        self.assertIn("Player1 (100)", result)
        self.assertIn("Player2 (50)", result)

    def test_template_with_events(self):
        """Шаблон показывает ближайшие ивенты."""
        result = digest.template({"events": [{"title": "PvP ивент", "starts_at": "2024-01-15 18:00"}]})
        self.assertIn("🎯 Ближайшие ивенты:", result)
        self.assertIn("PvP ивент", result)

    def test_template_all_facts(self):
        """Шаблон корректно формирует текст со всеми фактами."""
        result = digest.template({
            "online": "🟢 3 игрока онлайн",
            "messages_today": 150,
            "top": [{"name": "Alice", "messages": 200}, {"name": "Bob", "messages": 100}],
            "events": [{"title": "Квест", "starts_at": "2024-01-20 20:00"}]}
        )
        self.assertIn("📰 Итоги дня в PRISMA", result)
        self.assertIn("🟢 3 игрока онлайн", result)
        self.assertIn("💬 Сообщений в чате за сутки: 150", result)
        self.assertIn("🏆 Самые активные:", result)
        self.assertIn("Alice (200)", result)
        self.assertIn("🎯 Ближайшие ивенты:", result)
        self.assertIn("Квест", result)

if __name__ == "__main__":
    unittest.main()
