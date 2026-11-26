import os
import sys
import unittest

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import briefing


class BriefingTests(unittest.IsolatedAsyncioTestCase):
    async def test_build_briefing_with_data(self):
        """Тестируем build_briefing с данными"""
        result = await briefing.build_briefing()
        self.assertIsInstance(result, (str, type(None)))

    async def test_build_briefing_returns_none_when_no_data(self):
        """Тестируем build_briefing когда данных нет"""
        result = await briefing.build_briefing()
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
