from utils.validation import Validation

async def send_dashboard(message: types.Message, edit: bool = False) -> None:
    valid, err = Validation.validate_telegram_id(message.from_user.id, "Telegram ID")
    if not valid:
        logger.warning("Invalid Telegram ID in send_dashboard: %s", message.from_user.id)
        return
    if message.from_user is None or not await is_admin_mode(message.from_user.id):
        await message.answer("Нужен режим админа.")
        return

async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    valid, err = Validation.validate_telegram_id(tg_id, "Telegram ID")
    if not valid:
        logger.warning("Invalid Telegram ID in _home: %s", tg_id)
        return "❌ Ошибка: некорректный Telegram ID.", types.InlineKeyboardMarkup(inline_keyboard=[])
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)

async def _guard(callback: types.CallbackQuery, permission: str | None) -> bool:
    valid, err = Validation.validate_telegram_id(callback.from_user.id, "Telegram ID")
    if not valid:
        logger.warning("Invalid Telegram ID in _guard: %s", callback.from_user.id)
        return False
