from aiogram import types
from aiogram import Router, F
from db.rpc import bot_get_profile, bot_get_user_status
from services.ai import navigator, member_tools, memory as ai_memory
from utils.validation import Validation

free_router = Router()

is_configured = lambda: True

async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Вернуть статус пользователя для интента гида."""
    if kind not in ("guide", "apply"):
        return ""
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "ai", error)
        return ""
    return str(await bot_get_user_status(tg_id) or "")

async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Задать вопрос ИИ."""
    valid, error = Validation.validate_telegram_id(message.from_user.id)
    if not valid:
        Validation.log_warning("_ask_ai", message.from_user.id, "ai", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return False
    
    # Пустой вопрос — приветствие
    if not question or not question.strip():
        await message.answer("Привет")
        return True
    
    # Получаем статус пользователя
    status = await _status_for_intent(message.from_user.id, "guide")
    
    # Запускаем участника (ИИ)
    text, _ = await member_tools.run_member(
        tg_id=message.from_user.id,
        question=question,
        status=status,
        history=[],
        private=private,
        chat_context="",
        asker=message.from_user.first_name or "Пользователь",
        adult=0
    )
    
    if text:
        await message.answer(text)
    return True

async def _answer_by_code(message: types.Message, question: str, private: bool) -> bool:
    """Ответ по коду (fallback)."""
    return False

async def _answer(message: types.Message, question: str, private: bool) -> bool:
    """Главная точка входа для ответа."""
    if await _ask_ai(message, question, private):
        return True
    return await _answer_by_code(message, question, private)

# Регистрируем хендлер для свободного текста
@free_router.message(F.text)
async def _free_text_handler(message: types.Message):
    await _answer(message, message.text or "", message.chat.type == "private")

async def run_member(tg_id: int, question: str, status: str, history: list, private: bool, chat_context: str = "", asker: str = "", adult: int = 0):
    """Запуск участника."""
    return "", []