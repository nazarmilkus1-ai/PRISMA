async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для проверки доступа")
    if not valid:
        Validation.log_warning("_home", tg_id, "_home", error)
        return "❌ Неверный Telegram ID", types.InlineKeyboardMarkup(inline_keyboard=[])
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)