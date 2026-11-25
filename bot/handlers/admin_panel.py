async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    """Show admin home page."""
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        Validation.log_warning("_home", tg_id, "_home", error)
        return "⚠️ Некорректный ID пользователя", types.InlineKeyboardMarkup([])
    # ... existing code
