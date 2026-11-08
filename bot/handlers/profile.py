from aiogram import Router, types
from aiogram.filters import Command
from html import escape
from db.rpc import bot_get_profile
from utils.permissions import staff_context

router = Router()

@router.message(Command("profile"))
async def cmd_profile(message: types.Message):
    result = await bot_get_profile(message.from_user.id)
    if result.error or not isinstance(result.data, dict):
        await message.answer("❌ Не удалось получить профиль.")
        return
    if result.data.get("error") == "USER_NOT_FOUND":
        await message.answer("❌ Вы ещё не зарегистрированы. Нажмите /start.")
        return

    d = result.data
    clan = d.get("clan_id") or "—"
    staff = await staff_context(message.from_user.id)
    role = str(staff.get("role") or "participant")
    role_labels = {
        "participant": "УЧ — Учасник",
        "helper": "ХЕЛП — Хелпер",
        "moderator": "МДР — Модератор",
        "admin": "АДМ — Администратор",
        "head_staff": "ГС — Глава модерации",
        "head_admin": "ГА — Главный администратор",
        "senior_moderator": "СМДР — Старший модератор",
        "owner": "ВЛД — Власник",
        "developer": "ТЕХ — Developer / Tech Admin",
        "builder": "СТР — Builder / Map Maker",
        "game_designer": "GD — Game Designer",
        "event_manager": "ИВТ — Event Manager",
        "media": "МЕД — Media / Blogger",
        "content_maker": "КМ — Legacy Content Maker",
    }
    role_label = role_labels.get(role, role)
    await message.answer(
        "👤 <b>Ваш профиль PRISMA</b>\n\n"
        f"<b>Telegram:</b> @{escape(str(d.get('username') or '—').lstrip('@'))}\n"
        f"<b>Minecraft:</b> <code>{escape(str(d.get('minecraft_nick') or '—'))}</code>\n"
        f"<b>Whitelist:</b> {'✅' if d.get('is_whitelisted') else '❌'}\n"
        f"<b>Рейтинг:</b> {escape(str(d.get('rating', 0)))}\n"
        f"<b>Активность:</b> {escape(str(d.get('activity_score', 0)))}\n"
        f"<b>Уровень / XP:</b> {escape(str(d.get('level', 0)))} / {escape(str(d.get('xp', 0)))}\n"
        f"<b>Активных предупреждений:</b> {escape(str(d.get('active_warns', 0)))}\n"
        f"<b>Клан:</b> {escape(str(clan))}\n"
        f"<b>Роль PRISMA:</b> {escape(role_label)}",
        parse_mode="HTML",
    )
