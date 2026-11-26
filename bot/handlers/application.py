async def _ask_name(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    context = await staff_context(callback.from_user.id)
    valid, error = Validation.validate_telegram_id(context.get("tg_id", 0), "Telegram ID заявки")
    if not valid:
        logger.warning("_ask_name: invalid tg_id %s", context.get("tg_id"))
        await callback.message.edit_text("❌ Неверный Telegram ID.")
        return
    await _show_name_form(callback.message, state)