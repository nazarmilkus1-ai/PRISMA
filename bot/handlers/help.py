"""Short /help with per-section detail buttons (private chats)."""
from aiogram import F, Router, types
from aiogram.filters import Command
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

from utils.mode import ADMIN_MODE
from utils.permissions import ensure_mode, has_any_staff_permission

router = Router(name="help")

OVERVIEW = (
    "🤖 <b>PRISMA — помощь</b>\n\n"
    "Почти всё доступно кнопками в <code>/start</code>. Не знаете, с чего начать — <code>/guide</code>, а любой вопрос можно задать боту: <code>/ask как ...</code>.\n\n"
    "<code>/profile</code> — профиль · <code>/server</code> — сервер · <code>/top</code> — топ\n"
    "<code>/clan</code> — клан · <code>/events</code> — ивенты · <code>/market</code> — рынок\n"
    "<code>/report</code> — жалоба · <code>/support</code> — поддержка · <code>/rules</code> — правила\n"
    "<code>/cancel</code> — отменить текущее действие\n\n"
    "Выберите раздел, чтобы увидеть все команды:"
)

SECTIONS = {
    "start": (
        "🚀 <b>Начало</b>",
        "<code>/start</code> — главное меню\n"
        "<code>/wiki</code> — Wiki PRISMA\n"
        "<code>/application</code> — подать заявку на whitelist\n"
        "<code>/cancel</code> — отменить текущее действие",
    ),
    "player": (
        "👤 <b>Игрок</b>",
        "<code>/me</code> — центр игрока\n"
        "<code>/profile</code> — подробный профиль\n"
        "<code>/link</code> — изменить Minecraft-ник\n"
        "<code>/accounts</code> — Minecraft-аккаунты · <code>/addaccount</code> — Java + Bedrock в одном профиле\n"
        "<code>/addtg</code> — привязать второй Telegram-аккаунт\n"
        "<code>/stats</code> — игровая статистика\n"
        "<code>/achievements</code> — достижения\n"
        "<code>/top</code> — топ игроков\n"
        "<code>/battle НИК</code> — Player Battle · <code>/battles</code> — история\n"
        "<code>/mc_commands</code> — команды Minecraft и авторизация\n"
        "<code>/notifications</code> — настройки уведомлений",
    ),
    "community": (
        "👥 <b>Сообщество</b>",
        "<code>/server</code> — состояние сервера\n"
        "<code>/events</code> — ивенты и регистрация\n"
        "<code>/news</code> — новости · <code>/polls</code> — голосования\n"
        "<code>/market</code> — рынок · <code>/rate</code> — оценить сервер\n"
        "<code>/clan</code> — клан; <code>/клан приглашения</code>, <code>/клан война</code>, "
        "<code>/клан новости</code>, <code>/клан роль НИК РОЛЬ</code>\n"
        "<code>/отн @ник</code> — отношения · <code>/брак @ник</code> — брак · "
        "<code>/браки</code> — список",
    ),
    "reports": (
        "📢 <b>Жалобы и наказания</b>",
        "<code>/report</code> — жалоба на игрока · <code>/my_reports</code> — мои жалобы\n"
        "<code>/warnings</code> — активные наказания\n"
        "<code>/appeal</code> — апелляция · <code>/my_appeals</code> — мои апелляции\n"
        "<code>/support</code> — обращение в поддержку",
    ),
    "admin": (
        "🛡 <b>Администрация</b>",
        "<code>/admin</code> — админ-центр · <code>/players</code> — поиск игроков\n"
        "<code>/app_approve</code> / <code>/app_reject</code> — заявки\n"
        "<code>/report_status</code> — статус репорта\n"
        "<code>/appeal_review</code> / <code>/appeal_approve</code> / <code>/appeal_reject</code> — апелляции\n"
        "<code>/warn</code> <code>/mute</code> <code>/ban</code> <code>/kick</code> и "
        "<code>/unwarn</code> <code>/unmute</code> <code>/unban</code> — наказания\n"
        "<code>/history</code> — история наказаний\n"
        "<code>/poll_create</code> / <code>/finish_poll</code> — голосования\n"
        "<code>/support_list</code> / <code>/support_resolve</code> — поддержка",
    ),
}


async def _keyboard(tg_id: int, current: str | None):
    rows = [
        [InlineKeyboardButton(text="🚀 Начало", callback_data="help:start"),
         InlineKeyboardButton(text="👤 Игрок", callback_data="help:player")],
        [InlineKeyboardButton(text="👥 Сообщество", callback_data="help:community"),
         InlineKeyboardButton(text="📢 Жалобы", callback_data="help:reports")],
    ]
    if await ensure_mode(tg_id) == ADMIN_MODE and await has_any_staff_permission(tg_id):
        rows.append([InlineKeyboardButton(text="🛡 Администрация", callback_data="help:admin")])
    if current:
        rows.append([InlineKeyboardButton(text="↩️ К разделам", callback_data="help:home")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


async def _render(tg_id: int, section: str | None):
    if section in SECTIONS:
        title, body = SECTIONS[section]
        return f"{title}\n\n{body}", await _keyboard(tg_id, section)
    return OVERVIEW, await _keyboard(tg_id, None)


@router.message(Command("help"))
async def help_command(message: types.Message):
    text, markup = await _render(message.from_user.id, None)
    await message.answer(text, parse_mode="HTML", reply_markup=markup)


@router.callback_query(F.data == "menu:help")
async def help_from_menu(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        text, markup = await _render(callback.from_user.id, None)
        await callback.message.answer(text, parse_mode="HTML", reply_markup=markup)


@router.callback_query(F.data.startswith("help:"))
async def help_section(callback: types.CallbackQuery):
    await callback.answer()
    if not callback.message:
        return
    section = callback.data.split(":", 1)[1]
    if section == "admin" and not (
        await ensure_mode(callback.from_user.id) == ADMIN_MODE
        and await has_any_staff_permission(callback.from_user.id)
    ):
        return
    text, markup = await _render(callback.from_user.id, section)
    try:
        await callback.message.edit_text(text, parse_mode="HTML", reply_markup=markup)
    except Exception:
        await callback.message.answer(text, parse_mode="HTML", reply_markup=markup)
