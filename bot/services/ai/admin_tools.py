tg_id = row.get("telegram_id")
if not tg_id:
    member = None
else:
    ok, _ = Validation.validate_telegram_id(int(tg_id))
    if not ok:
        logger.warning("Invalid Telegram ID in admin_tools: %s", tg_id)
        member = None
    else:
        member = await ctx.bot.get_chat_member(MODERATION_GROUP_ID, int(tg_id))