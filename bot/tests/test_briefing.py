import os
import sys
import unittest
from unittest.mock import AsyncMock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "[скрыто]")
os.environ.setdefault("BOT_TOKEN", "123456:TEST")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services import briefing


class BriefingTests(unittest.IsolatedAsyncioTestCase):
    async def test_build_briefing_with_data(self):
        """Тестируем build_briefing с данными"""
        with patch("services.briefing.bot_get_pending_count", AsyncMock(return_value=5)), \
             patch("services.briefing.open_reports", AsyncMock(return_value=[])), \
             patch("services.briefing.open_appeals", AsyncMock(return_value=[])), \
             patch("services.briefing.bot_list_inactive_members", AsyncMock(return_value=type('obj', (object,), {'data': [], 'error': None, 'isinstance': lambda self, x: isinstance(x, list)})())):
            result = await briefing.build_briefing()
            self.assertIsInstance(result, str)
            self.assertIn("Утренний брифинг", result)

    async def test_build_briefing_returns_none_when_no_data(self):
        """Тестируем build_briefing когда данных нет"""
        with patch("services.briefing.bot_get_pending_count", AsyncMock(return_value=0)), \
             patch("services.briefing.open_reports", AsyncMock(return_value=[])), \
             patch("services.briefing.open_appeals", AsyncMock(return_value=[])), \
             patch("services.briefing.bot_list_inactive_members", AsyncMock(return_value=type('obj', (object,), {'data': [], 'error': None, 'isinstance': lambda self, x: isinstance(x, list)})())):
            result = await briefing.build_briefing()
            self.assertIsNone(result)

    async def test_build_briefing_with_mixed_data(self):
        """Тестируем build_briefing с частичными данными"""
        with patch("services.briefing.bot_get_pending_count", AsyncMock(return_value=3)), \
             patch("services.briefing.open_reports", AsyncMock(return_value=[])), \
             patch("services.briefing.open_appeals", AsyncMock(return_value=[])), \
             patch("services.briefing.bot_list_inactive_members", AsyncMock(return_value=type('obj', (object,), {'data': [], 'error': None, 'isinstance': lambda self, x: isinstance(x, list)})())):
            result = await briefing.build_briefing()
            self.assertIsInstance(result, str)
            self.assertIn("Заявок ждут решения: <b>3</b>", result)
