from aiogram import Router, types, F
from utils.validation import Validation
from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment

router = Router(name="ban_review")


CB_PREFIX = "ban_review"


async def on_decision(call: types.CallbackQuery):
    """Обрабатывает решение по бану: разбан или приглашение в чат."""
    data = call.data.split(":")
    action = data[1]
    tg_id = int(data[2])

    if action == "ok":
        # Подтвердить разбан
        await bot_lift_punishment(tg_id, "BAN", call.from_user.id)
        await call.bot.unban_chat_member(call.message.chat.id, tg_id, only_if_banned=True)
        await call.message.edit_text("Вы подтвердили разбан")
    elif action == "keep":
        # Оставить как есть - вызвать сервис удержания
        from services.ban_review import bot_ban_review_keep
        await bot_ban_review_keep(tg_id, call.from_user.id)
        await call.message.edit_text("Вы оставили бан в силе")
    else:
        await call.answer("Неизвестное действие", show_alert=True)