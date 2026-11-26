import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from aiogram import types
from handlers.chat_commands import _resolve_target
from utils.validation import Validation


class TestResolveTarget:
    """Тесты для _resolve_target."""

    @pytest.mark.asyncio
    async def test_resolve_target_from_reply_valid(self):
        """Тест: корректный пользователь из reply."""
        message = MagicMock(spec=types.Message)
        reply_user = MagicMock(spec=types.User)
        reply_user.id = 123456789
        reply_user.username = "testuser"
        reply_user.first_name = "Test"
        reply_user.last_name = "User"
        reply_user.full_name = "Test User"
        reply_user.is_bot = False
        
        message.reply_to_message = MagicMock()
        message.reply_to_message.from_user = reply_user
        
        with patch('handlers.chat_commands.bot_touch_user', new_callable=AsyncMock) as mock_touch:
            result, args = await _resolve_target(message, [])
            
        assert result is not None
        assert result["tg_id"] == 123456789
        assert result["username"] == "testuser"
        assert result["full_name"] == "Test User"
        assert result["minecraft_nick"] is None
        mock_touch.assert_called_once()

    @pytest.mark.asyncio
    async def test_resolve_target_from_reply_invalid_id(self):
        """Тест: невалидный Telegram ID из reply."""
        message = MagicMock(spec=types.Message)
        reply_user = MagicMock(spec=types.User)
        reply_user.id = -1  # невалидный ID
        reply_user.username = "testuser"
        reply_user.first_name = "Test"
        reply_user.last_name = "User"
        reply_user.full_name = "Test User"
        reply_user.is_bot = False
        
        message.reply_to_message = MagicMock()
        message.reply_to_message.from_user = reply_user
        
        with patch('handlers.chat_commands.bot_touch_user', new_callable=AsyncMock) as mock_touch:
            result, args = await _resolve_target(message, [])
            
        assert result is None
        mock_touch.assert_not_called()

    @pytest.mark.asyncio
    async def test_resolve_target_from_search_valid(self):
        """Тест: корректный пользователь из поиска."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        mock_result = MagicMock()
        mock_result.error = None
        mock_result.data = {
            "tg_id": 123456789,
            "username": "testuser",
            "full_name": "Test User",
            "minecraft_nick": "Player123"
        }
        
        with patch('handlers.chat_commands.bot_find_user', new_callable=AsyncMock, return_value=mock_result) as mock_find:
            result, args = await _resolve_target(message, ["testuser"])
            
        assert result is not None
        assert result["tg_id"] == 123456789
        assert result["username"] == "testuser"
        assert result["minecraft_nick"] == "Player123"
        mock_find.assert_called_once_with("testuser")

    @pytest.mark.asyncio
    async def test_resolve_target_from_search_error(self):
        """Тест: ошибка при поиске пользователя."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        mock_result = MagicMock()
        mock_result.error = "User not found"
        mock_result.data = None
        
        with patch('handlers.chat_commands.bot_find_user', new_callable=AsyncMock, return_value=mock_result) as mock_find:
            result, args = await _resolve_target(message, ["unknown"])
            
        assert result is None
        mock_find.assert_called_once_with("unknown")

    @pytest.mark.asyncio
    async def test_resolve_target_from_search_invalid_tg_id(self):
        """Тест: невалидный Telegram ID в результате поиска."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        mock_result = MagicMock()
        mock_result.error = None
        mock_result.data = {
            "tg_id": -1,  # невалидный ID
            "username": "testuser",
            "full_name": "Test User"
        }
        
        with patch('handlers.chat_commands.bot_find_user', new_callable=AsyncMock, return_value=mock_result) as mock_find:
            result, args = await _resolve_target(message, ["testuser"])
            
        assert result is None
        mock_find.assert_called_once_with("testuser")

    @pytest.mark.asyncio
    async def test_resolve_target_no_args(self):
        """Тест: нет аргументов и нет reply."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        result, args = await _resolve_target(message, [])
        
        assert result is None
        assert args == []

    @pytest.mark.asyncio
    async def test_resolve_target_telegram_username_fallback(self):
        """Тест: fallback на telegram_username."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        mock_result = MagicMock()
        mock_result.error = None
        mock_result.data = {
            "tg_id": 123456789,
            "telegram_username": "testuser",
            "full_name": "Test User"
        }
        
        with patch('handlers.chat_commands.bot_find_user', new_callable=AsyncMock, return_value=mock_result) as mock_find:
            result, args = await _resolve_target(message, ["testuser"])
            
        assert result is not None
        assert result["username"] == "testuser"
        mock_find.assert_called_once_with("testuser")

    @pytest.mark.asyncio
    async def test_resolve_target_minecraft_nickname_fallback(self):
        """Тест: fallback на minecraft_nickname."""
        message = MagicMock(spec=types.Message)
        message.reply_to_message = None
        
        mock_result = MagicMock()
        mock_result.error = None
        mock_result.data = {
            "tg_id": 123456789,
            "username": "testuser",
            "full_name": "Test User",
            "minecraft_nickname": "Player123"
        }
        
        with patch('handlers.chat_commands.bot_find_user', new_callable=AsyncMock, return_value=mock_result) as mock_find:
            result, args = await _resolve_target(message, ["testuser"])
            
        assert result is not None
        assert result["minecraft_nick"] == "Player123"
        mock_find.assert_called_once_with("testuser")
