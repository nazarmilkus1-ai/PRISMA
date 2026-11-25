async def reminders_tool(name: str, args: dict, tg_id: int) -> dict:
    ok, _ = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in reminders_tool: %s", tg_id)
        return {"reminders": []}
    # rest of function