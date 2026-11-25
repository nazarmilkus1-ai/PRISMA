from utils.validation import Validation

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
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in admin_panel _home: %s", error)
        return "❌ Неверный идентификатор пользователя", types.InlineKeyboardMarkup(inline_keyboard=[])
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)