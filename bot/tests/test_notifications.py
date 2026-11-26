import os
import sys
import unittest

os.environ.update(
    SUPABASE_URL="http://127.0.0.1:54321",
    SUPABASE_ANON_KEY="test",
    BOT_TOKEN="1:x",
    MODERATION_GROUP_ID="-100123",
)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import notifications  # noqa: E402


class NotificationTests(unittest.TestCase):
    def setUp(self):
        pass

    def test_module_imports(self):
        """Проверяем, что модуль notifications можно импортировать"""
        self.assertIsNotNone(notifications)

    def test_kind_to_pref_mapping(self):
        """Проверяем словарь сопоставления kind и preference"""
        from services.notifications import KIND_TO_PREF
        self.assertIn("NEWS", KIND_TO_PREF)
        self.assertIn("EVENT", KIND_TO_PREF)
        self.assertIn("SERVER_STATUS", KIND_TO_PREF)


if __name__ == "__main__":
    unittest.main()
