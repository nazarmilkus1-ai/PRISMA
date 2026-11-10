from aiogram import F, Router, types
from aiogram.fsm.context import FSMContext

from config import PANEL_URL
from db.rpc import bot_get_user_status
from keyboards.inline import (
    admin_menu,
    community_menu_keyboard,
    main_menu_approved,
    main_menu_before_apply,
    main_menu_pending,
    moderation_menu_keyboard,
    player_menu_keyboard,
)
from handlers.clans import cmd_clan
from handlers.polls import cmd_polls
from handlers.reports import cmd_report
from utils.commands import set_user_commands
from utils.mode import ADMIN_MODE, PARTICIPANT_MODE, set_mode
from utils.permissions import ensure_mode, has_any_staff_permission


router = Router()

TEXTS = {
    "about_prisma": (
        "📖 <b>О PRISMA</b>\n\n"
        "Сообщество Minecraft-сервера с whitelist. Через этого бота вы подаёте заявку, "
        "получаете решение и пользуетесь сообществом: профиль, топ, кланы, ивенты, рынок и голосования."
    ),
    "about_server": (
        "🌐 <b>О сервере</b>\n\n"
        "Полу-ванильный Minecraft-сервер с whitelist, сообществом, кланами и голосованиями.\n\n"
        "Чтобы зайти, подайте заявку: после одобрения вы попадёте в whitelist."
    ),
}

SECTION_TEXTS = {
    "menu:player": "➕ <b>Ещё</b>\n\nСтатистика, достижения, Player Battle, команды Minecraft, Minecraft-ник и авторизация.",
    "menu:community": "👥 <b>Сообщество</b>\n\nИвенты, кланы, новости и активные голосования.",
    "menu:moderation": "⚖️ <b>Жалобы и модерация</b>\n\nСоздание жалоб, история ваших жалоб, активные наказания и апелляции.",
    "menu:help": "❓ <b>Помощь</b>\n\nПолный список всех возможностей: /help",
}


async def _show(message: types.Message, text: str, markup):
    """Edit the menu message in place; fall back to a new message if Telegram refuses."""
    try:
        await message.edit_text(text, parse_mode="HTML", reply_markup=markup)
    except Exception:
        await message.answer(text, parse_mode="HTML", reply_markup=markup)


async def _menu_for(tg_id: int):
    mode = await ensure_mode(tg_id)
    if mode == ADMIN_MODE:
        return admin_menu(PANEL_URL)

    status = await bot_get_user_status(tg_id)
    show_admin_switch = await has_any_staff_permission(tg_id)
    if status == "ACCEPTED":
        return main_menu_approved(show_admin_switch=show_admin_switch)
    if status in ("NO_USER", "NO_APPLICATION", "REJECTED"):
        return main_menu_before_apply(show_admin_switch=show_admin_switch)
    return main_menu_pending(show_admin_switch=show_admin_switch)


@router.callback_query(F.data == "mode:participant")
async def switch_to_participant(callback: types.CallbackQuery):
    if not await has_any_staff_permission(callback.from_user.id):
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return

    await set_mode(callback.from_user.id, PARTICIPANT_MODE)
    await set_user_commands(callback.bot, callback.from_user.id, admin=False)
    await callback.answer("👤 Включён режим участника.")

    if callback.message:
        await callback.message.edit_text(
            "👤 <b>Режим участника</b>\n\n"
            "Теперь вы видите интерфейс обычного игрока.",
            parse_mode="HTML",
            reply_markup=await _menu_for(callback.from_user.id),
        )


@router.callback_query(F.data == "mode:admin")
async def switch_to_admin(callback: types.CallbackQuery):
    if not await has_any_staff_permission(callback.from_user.id):
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return

    await set_mode(callback.from_user.id, ADMIN_MODE)
    await set_user_commands(callback.bot, callback.from_user.id, admin=True)
    await callback.answer("🛡 Включён режим администратора.")

    if callback.message:
        from handlers.admin_panel import send_dashboard
        await send_dashboard(callback.message, edit=True)


@router.callback_query(F.data.in_(set(SECTION_TEXTS)))
async def section_menu(callback: types.CallbackQuery):
    await callback.answer()
    if not callback.message:
        return
    markup = {
        "menu:player": player_menu_keyboard(),
        "menu:community": community_menu_keyboard(),
        "menu:moderation": moderation_menu_keyboard(),
        "menu:help": None,
    }[callback.data]
    await _show(callback.message, SECTION_TEXTS[callback.data], markup)


def _as_command(callback: types.CallbackQuery, command: str) -> types.Message:
    """The callback's message belongs to the bot; re-attribute it to the clicking user."""
    return callback.message.model_copy(update={"from_user": callback.from_user, "text": command})


@router.callback_query(F.data == "clans")
async def clans_button(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await cmd_clan(_as_command(callback, "/clan"), state)


@router.callback_query(F.data == "polls")
async def polls_button(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await cmd_polls(_as_command(callback, "/polls"))


@router.callback_query(F.data == "reports")
async def report_button(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await cmd_report(_as_command(callback, "/report"), state)


@router.callback_query(F.data == "menu:link")
async def link_menu(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await callback.message.answer("🔗 Для изменения Minecraft-ника используйте /link.")


@router.callback_query(F.data == "menu:back")
async def menu_back(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _show(
            callback.message,
            "🏠 <b>Главное меню PRISMA</b>\n\nВыберите нужный раздел:",
            await _menu_for(callback.from_user.id),
        )


@router.callback_query(F.data.in_(set(TEXTS)))
async def menu_button(callback: types.CallbackQuery):
    await callback.answer()
    if not callback.message:
        return
    markup = await _menu_for(callback.from_user.id)
    await callback.message.answer(TEXTS[callback.data], parse_mode="HTML", reply_markup=markup)


@router.callback_query()
async def stale_callback(callback: types.CallbackQuery):
    await callback.answer("Кнопка устарела. Откройте /start.", show_alert=True)
