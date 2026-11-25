from utils.permissions import require_admin_mode_callback, staff_context
from utils.validation import Validation

router = Router(name="admin_panel")


class PanelStates(StatesGroup):
    find_player = State()


async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    valid, error = Validation.validate_telegram_id(tg_id, "_home")
    if not valid:
        Validation.log_warning("_home", tg_id, "_home", error)
        return "❌ Неверный идентификатор пользователя.", types.InlineKeyboardMarkup(inline_keyboard=[])
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)
