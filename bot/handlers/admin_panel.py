"""Staff panel: one entry point (/admin or the «Админ-панель» button), a live dashboard,
and section screens. Writes stay in handlers/admin_actions (confirm buttons + per-click checks)."""
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup

from config import PANEL_URL
from db.admin import find_players
from db.player import get_online_players
from db.rpc import bot_get_player_activity_stats, bot_get_server_metrics, bot_get_server_status, bot_list_inactive_members, bot_list_staff, bot_list_support_requests
from keyboards.admin_actions import support_actions
from keyboards.admin_panel import back_row, home_keyboard, section_keyboard
from services import admin_dashboard
from services.ai import diagnostics
from utils.commands import set_user_commands
from utils.mode import ADMIN_MODE, set_mode
from utils.permissions import require_admin_mode_callback, staff_context

router = Router(name="admin_panel")


class PanelStates(StatesGroup):
    find_player = State()


async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)


async def send_dashboard(message: types.Message, edit: bool = False) -> None:
    text, markup = await _home(message.chat.id if edit else message.from_user.id)
    if edit:
        try:
            await message.edit_text(text, parse_mode="HTML", reply_markup=markup)
            return
        except Exception:
            pass
    await message.answer(text, parse_mode="HTML", reply_markup=markup)


@router.message(Command("admin", "panel"))
async def admin_entry(message: types.Message, state: FSMContext):
    """Entry point: staff are switched into admin mode automatically; others are told plainly."""
    await state.clear()
    context = await staff_context(message.from_user.id)
    if not context.get("is_staff"):
        await message.answer("❌ Админ-панель доступна только персоналу PRISMA.")
        return
    await set_mode(message.from_user.id, ADMIN_MODE)
    await set_user_commands(message.bot, message.from_user.id, admin=True)
    await send_dashboard(message)


@router.callback_query(F.data == "ap:home")
async def home_callback(callback: types.CallbackQuery, state: FSMContext):
    if not await require_admin_mode_callback(callback):
        return
    await state.clear()
    await callback.answer("Обновлено")
    if callback.message:
        await send_dashboard(callback.message, edit=True)


async def _guard(callback: types.CallbackQuery, permission: str | None) -> bool:
    if not await require_admin_mode_callback(callback):
        return False
    if permission:
        from db.rpc import bot_check_admin_permission
        result = await bot_check_admin_permission(callback.from_user.id, permission)
        if result.error or not result.data:
            await callback.answer("❌ Недостаточно прав.", show_alert=True)
            return False
    await callback.answer()
    return True


async def _show(callback: types.CallbackQuery, text: str, markup: types.InlineKeyboardMarkup) -> None:
    try:
        await callback.message.edit_text(text, parse_mode="HTML", reply_markup=markup)
    except Exception:
        await callback.message.answer(text, parse_mode="HTML", reply_markup=markup)


_SECTION_TITLES = {
    "people": ("👥 <b>Люди</b>\n\nПоиск, кто онлайн, кто пропал и кто в команде.", "player.view"),
    "mod": ("🛡 <b>Модерация</b>\n\nЖалобы, апелляции, автомод и команды наказаний.", "punishment.view_history"),
    "sys": ("🖥 <b>Система</b>\n\nСостояние сервера и диагностика бота.", "system.health"),
}


@router.callback_query(F.data.in_({"ap:people", "ap:mod", "ap:sys"}))
async def section(callback: types.CallbackQuery):
    key = callback.data.split(":", 1)[1]
    title, permission = _SECTION_TITLES[key]
    if not await _guard(callback, permission):
        return
    perms = (await staff_context(callback.from_user.id)).get("permissions") or []
    await _show(callback, title, section_keyboard(key, perms, PANEL_URL))


def _back() -> types.InlineKeyboardMarkup:
    return types.InlineKeyboardMarkup(inline_keyboard=[back_row()])


@router.callback_query(F.data == "ap:online")
async def online(callback: types.CallbackQuery):
    if not await _guard(callback, "player.view"):
        return
    rows, err = await get_online_players()
    if err:
        await _show(callback, "❌ Список онлайна недоступен.", _back())
        return
    names = [str(r.get("minecraft_nickname") or "").strip() for r in rows if isinstance(r, dict)]
    names = [n for n in names if n][:60]
    body = "\n".join(f"• <code>{escape(n)}</code>" for n in names) or "Никого нет онлайн."
    await _show(callback, f"🟢 <b>Сейчас онлайн: {len(names)}</b>\n\n{body}", _back())


@router.callback_query(F.data == "ap:inactive")
async def inactive(callback: types.CallbackQuery):
    if not await _guard(callback, "player.view"):
        return
    result = await bot_list_inactive_members(7, 40)
    rows = result.data if not result.error and isinstance(result.data, list) else None
    if rows is None:
        await _show(callback, "❌ Не удалось загрузить список.", _back())
        return
    lines = [f"• {escape(str(r.get('display_name') or r.get('username') or '—'))}"
             f" — <code>{escape(str(r.get('last_seen_at') or '—'))}</code>" for r in rows[:30]]
    await _show(callback, f"💤 <b>Неактивны 7+ дней: {len(rows)}</b>\n\n" + ("\n".join(lines) or "Таких нет."), _back())


@router.callback_query(F.data == "ap:staff")
async def staff(callback: types.CallbackQuery):
    if not await _guard(callback, "player.view"):
        return
    result = await bot_list_staff()
    rows = result.data if not result.error and isinstance(result.data, list) else None
    if rows is None:
        await _show(callback, "❌ Не удалось загрузить персонал.", _back())
        return
    lines = [f"• {escape(str(r.get('display_name') or r.get('username') or r.get('telegram_username') or '—'))}"
             f" — {escape(str(r.get('role_name') or r.get('role') or '—'))}" for r in rows[:40]]
    await _show(callback, f"👮 <b>Персонал: {len(rows)}</b>\n\n" + ("\n".join(lines) or "Пусто."), _back())


@router.callback_query(F.data == "ap:server")
async def server(callback: types.CallbackQuery):
    if not await _guard(callback, "system.health"):
        return
    status = await bot_get_server_status()
    metrics = await bot_get_server_metrics()
    s = status.data if not status.error and isinstance(status.data, dict) else {}
    m = metrics.data if not metrics.error and isinstance(metrics.data, dict) else {}
    text = (
        "🖥 <b>Сервер</b>\n\n"
        f"Статус: <b>{escape(str(s.get('status') or 'нет данных').upper())}</b>\n"
        f"Ноды: {s.get('online_nodes', '—')}/{s.get('total_nodes', '—')}\n"
        f"Онлайн: <b>{m.get('online_players', '—')}/{m.get('max_players', '—')}</b>\n"
        f"Версия: <b>{escape(str(m.get('version') or '—'))}</b>"
    )
    await _show(callback, text, _back())


@router.callback_query(F.data == "ap:errors")
async def errors(callback: types.CallbackQuery):
    if not await _guard(callback, "system.health"):
        return
    lines = diagnostics.recent_errors(15)
    body = "\n".join(escape(line[:200]) for line in lines) or "С момента запуска предупреждений не было ✅"
    await _show(callback, f"⚠️ <b>Ошибки бота</b> (секреты скрыты)\n\n<pre>{body}</pre>"[:4000], _back())


@router.callback_query(F.data == "ap:support")
async def support(callback: types.CallbackQuery):
    if not await _guard(callback, "player.view"):
        return
    result = await bot_list_support_requests(callback.from_user.id, "OPEN", 10)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        await _show(callback, "❌ Не удалось загрузить обращения.", _back())
        return
    items = data.get("items") or []
    await _show(callback, f"🆘 <b>Открытые обращения: {len(items)}</b>" + ("" if items else "\n\nВсё разобрано ✅"), _back())
    for row in items[:10]:
        ticket = str(row.get("ticket_no") or "")
        if not ticket.isdigit():
            continue
        await callback.message.answer(
            f"🆘 <b>#{escape(ticket)}</b> · {escape(str(row.get('telegram_username') or '—'))}\n{escape(str(row.get('message') or '')[:500])}",
            parse_mode="HTML", reply_markup=support_actions(ticket))


@router.callback_query(F.data == "ap:find")
async def find_start(callback: types.CallbackQuery, state: FSMContext):
    if not await _guard(callback, "player.view"):
        return
    await state.set_state(PanelStates.find_player)
    await _show(callback, "🔎 Отправьте ник, @username или Telegram ID игрока.", _back())


@router.message(StateFilter(PanelStates.find_player), F.text, ~F.text.startswith("/"))
async def find_result(message: types.Message, state: FSMContext):
    context = await staff_context(message.from_user.id)
    if not context.get("is_staff"):
        await state.clear()
        return
    await state.clear()
    rows, err = await find_players(message.from_user.id, (message.text or "").strip()[:64])
    if err:
        await message.answer("❌ Поиск не удался.", reply_markup=_back())
        return
    if not rows:
        await message.answer("👥 Игроки не найдены.", reply_markup=_back())
        return
    for row in rows[:5]:
        stats = await bot_get_player_activity_stats(row.get("telegram_id"))
        last = stats.data.get("last_activity") if not stats.error and isinstance(stats.data, dict) else None
        nick = row.get("minecraft_nickname") or row.get("telegram_username") or "Игрок"
        await message.answer(
            f"👤 <b>{escape(str(nick))}</b>\n"
            f"Telegram: <code>{row.get('telegram_id')}</code> · @{escape(str(row.get('telegram_username') or '—'))}\n"
            f"Статус: {escape(str(row.get('status') or '—'))} · whitelist {'✅' if row.get('is_whitelisted') else '❌'}\n"
            f"Уровень / XP: {row.get('level', 1)} / {row.get('xp', 0)} · рейтинг {row.get('rating', 0)}\n"
            f"Последняя активность: <code>{escape(str(last or 'нет данных'))}</code>",
            parse_mode="HTML",
        )
    await message.answer("Дальше: /history ник · /warn · /mute · /ban — или спросите PRISMA_AGENT.", reply_markup=_back())
