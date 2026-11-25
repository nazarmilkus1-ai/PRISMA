from aiogram import Router, types
from db.rpc import bot_get_profile, bot_get_user_status
from services.ai import ambient, navigator, sections, memory as ai_memory
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
    """Обработать вопрос участника: сначала пробуем ИИ, при неудаче — кодовый фоллбэк."""
    if not is_configured():
        await _answer_by_code(message, question, private)
        return True
    ok = await _ask_ai(message, question, private)
    if not ok:
        await _answer_by_code(message, question, private)
    return True


async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Запустить ИИ-ответ через run_member и отправить результат пользователю."""
    from services.ai.member_tools import Context
    
    # Получаем статус заявки пользователя
    status = await bot_get_user_status(message.from_user.id)
    
    # Определяем chat_id для группового чата
    chat_id = message.chat.id if not private else 0
    can_mute = False
    if not private:
        # Проверяем права на мут через navigator
        can_mute = await navigator.allowed(message.from_user.id, "mute")
    
    ctx = Context(
        tg_id=message.from_user.id,
        private=private,
        accepted=status == "ACCEPTED",
        chat_id=chat_id,
        can_mute=can_mute
    )
    
    # Получаем контекст чата для группового чата
    chat_context = ""
    asker = message.from_user.first_name or "участник"
    if not private:
        chat_context = ambient.transcript(chat_id, 40) or ""
        # Обновляем ambient с текущим сообщением
        ambient.observe(chat_id, message.message_id, message.from_user.id, asker, question)
    
    # Загружаем память пользователя
    await ai_memory.hydrate(ctx.tg_id)
    
    try:
        text, cards = await run_member(
            ctx.tg_id,
            question,
            status,
            [],  # history - будет загружена внутри run_member через memory
            private,
            chat_context=chat_context,
            asker=asker,
            adult=ambient.adult(chat_id) if not private else 0
        )
    except AIError:
        return False
    
    # Отправляем ответ
    if text:
        await message.answer(text)
    
    # Отправляем карточки, если есть
    for card_text, markup in ctx.cards:
        await message.answer(card_text, reply_markup=markup, parse_mode="HTML")
    
    # Сохраняем память
    await ai_memory.persist(ctx.tg_id)
    
    return True


async def _answer_by_code(message: types.Message, question: str, private: bool):
    """Отвечает заготовленным текстом (фоллбэк)."""
    from services.ai.sections import answer_by_code
    text = answer_by_code(question, private)
    if text:
        await message.answer(text)


# Реэкспорт для тестов
__all__ = [
    "free_router",
    "_ask_ai",
    "_answer_by_code",
    "run_member",
    "is_configured",
    "navigator",
    "ai_memory",
    "_answer",
]
