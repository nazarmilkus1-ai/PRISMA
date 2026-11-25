from utils.validation import Validation

router = Router()


async def _show_info(message: types.Message, tg_id: int):
    valid, error = Validation.validate_telegram_id(tg_id, "_show_info")
    if not valid:
        Validation.log_warning("_show_info", tg_id, "_show_info", error)
        await message.answer("❌ Неверный идентификатор пользователя.")
        return
    result = await bot_get_clan_info(tg_id)
    if result.error:
        await message.answer("❌ Не удалось получить данные клана.")
        return