from aiogram import Router, types, FSMContext
from utils.validation import Validation

router = Router()


@router.message(Command("application"))
async def application_command(message: types.Message, state: FSMContext):
    user_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(user_id, "application_command")
    if not valid:
        Validation.log_warning("application_command", user_id, "application_command", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    status = await bot_get_user_status(user_id)
    if status in ("PENDING", "ACCEPTED"):
        await message.answer("🔒 Быстрые действия открываются после одобрения заявки: /guide")
        return
    if status == "ERROR":
        await message.answer("❌ Ошибка соединения с базой данных.")
        return
    await bot_touch_user(
        message.from_user.id,
        message.from_user.username or "",
        message.from_user.first_name or "",
        message.from_user.last_name or "",
        message.from_user.full_name,
        "PRIVATE",
    )
    await state.set_state(ApplicationForm.agreement)
    await message.answer(
        "📝 <b>Подача заявки</b>\n\n"
        "Подавая заявку, вы принимаете правила PRISMA — прочитать их можно командой /rules.\n\n"
        "<b>Разрешаете обработку данных для работы сервера?</b>",
        reply_markup=agreement_keyboard(),
        parse_mode="HTML",
    )