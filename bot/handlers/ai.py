async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Задать вопрос ИИ."""
    valid, error = Validation.validate_telegram_id(message.from_user.id)
    if not valid:
        Validation.log_warning("_ask_ai", message.from_user.id, "ai", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return False
    # Логика ответа от ИИ
    await message.answer("✅ Вопрос обработан.")
    return True