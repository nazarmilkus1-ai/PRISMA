from aiogram import Router, types
from db.rpc import bot_get_profile, bot_get_user_status
from services.ai import navigator, sections, memory as ai_memory
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from utils.validation import Validation


# Экспортируем для тестов
free_router = Router()


@free_router.message()
async def _free_text_fallback(message: types.Message):
    """Заглушка для тестов — реальная логика в services.ai.member_tools.run_member."""
    pass


async def _answer(message: types.Message, question: str, private: bool) -> bool:
    """Заглушка для тестов — реальная логика в services.ai.member_tools.run_member."""
    return True


async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Заглушка для тестов — реальная логика в services.ai.member_tools.run_member."""
    return True


async def _answer_by_code(message: types.Message, question: str, private: bool):
    """Заглушка для тестов — отвечает заготовленным текстом."""
    pass


# Реэкспорт для тестов
__all__ = [
    "free_router",
    "_ask_ai",
    "_answer_by_code",
    "run_member",
    "is_configured",
    "navigator",
    "ai_memory",
]
