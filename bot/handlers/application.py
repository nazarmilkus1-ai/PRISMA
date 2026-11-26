async def _ask_name(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    context = await staff_context(callback.from_user.id)
    tg_id = context.get("tg_id", 0)
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID заявки")
    if not valid:
        logger.warning("_ask_name: invalid tg_id %s", tg_id)
        await callback.message.edit_text("❌ Неверный Telegram ID.")
        return
    await _show_name_form(callback.message, state)

async def _check_status(message: types.Message):
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID заявки")
    if not valid:
        logger.warning("_check_status: invalid tg_id %s", tg_id)
        await message.answer("❌ Неверный Telegram ID.")
        return
    status = await bot_get_user_status(tg_id)
    # ... rest of function