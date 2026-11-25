import time
from aiogram import Router, types, F
from utils.validation import Validation
from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment
from services import ban_review as ban_review_service

router = Router(name="ban_review")


CB_PREFIX = "ban_review"


async def on_decision(call: types.CallbackQuery):
    """Обрабатывает решение по бану: разбан или приглашение в чат."""
    data = call.data.split(":")
    action = data[1]
    tg_id = int(data[2])
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID из callback_data")
    if not valid:
        await call.answer(error, show_alert=True)
        return

    if action == "ok":
        # Подтвердить разбан
        result = await bot_lift_punishment(tg_id, "BAN", call.from_user.id)
        if result.error:
            await call.answer(result.error, show_alert=True)
            return
        # Получаем ID чата из RPC и unbanned в чате сообщества
        chat = await ban_review_service.bot_get_community_chat_id()
        chat_id = chat.data if not chat.error and isinstance(chat.data, int) else None
        if chat_id is not None:
            await call.bot.unban_chat_member(chat_id, tg_id, only_if_banned=True)
            # Создаём пригласительную ссылку и отправляем игроку
            try:
                created = await call.bot.create_chat_invite_link(
                    chat_id, name="return after ban", member_limit=1, expire_date=int(time.time()) + 7 * 24 * 3600
                )
                link = created.invite_link
            except Exception:
                link = None
            text = "✅ Срок бана закончился, администратор подтвердил ваше возвращение в PRISMA."
            text += f"\nВот ссылка для входа в чат (действует 7 дней, один вход):\n{link}" if link else "\nЗайдите обратно в чат сообщества."
            try:
                await call.bot.send_message(tg_id, text, disable_web_page_preview=True)
            except Exception:
                pass
        await call.message.edit_text("Вы подтвердили разбан")
    elif action == "keep":
        # Оставить как есть - вызвать сервис удержания
        result = await bot_ban_review_keep(tg_id, call.from_user.id)
        if result.error:
            await call.answer(result.error, show_alert=True)
            return
        await call.message.edit_text("Вы оставили бан в силе")
    else:
        await call.answer("Неизвестное действие", show_alert=True)