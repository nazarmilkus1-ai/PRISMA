async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Задать вопрос ИИ."""
    valid, error = Validation.validate_telegram_id(message.from_user.id)
    if not valid:
        Validation.log_warning("_ask_ai", message.from_user.id, "ai", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return False
    # Логика ответа от ИИ
    text, cards = await run_member(message.from_user.id, question, None, [], True)
    if text is None:
        await message.answer("❌ Не удалось получить ответ от ИИ.")
        return False
    await message.answer("✅ Вопрос обработан.")
    return True