async def _answer_by_code(message: types.Message, question: str, private: bool):
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI")
    if not valid:
        logger.warning("_answer_by_code: invalid tg_id %s", tg_id)
        await message.answer("❌ Неверный Telegram ID.")
        return
    kind = navigator.fast_kind(question)