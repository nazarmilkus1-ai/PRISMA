from db.rpc import bot_check_admin_permission, bot_get_profile, bot_get_staff_context
from utils.mode import ADMIN_MODE, PARTICIPANT_MODE, get_mode, set_mode


DENIED_MESSAGE = "⏳ Эта функция доступна после одобрения заявки администрацией. Проверить статус — /profile."


async def staff_context(tg_id: int) -> dict:
    result = await bot_get_staff_context(tg_id)
    if result.error or not isinstance(result.data, dict):
        return {"is_staff": False, "role": None, "permissions": []}

    permissions = result.data.get("permissions")
    if not isinstance(permissions, list):
        permissions = []

    return {
        "is_staff": bool(result.data.get("is_staff")),
        "role": result.data.get("role"),
        "permissions": [str(value) for value in permissions],
    }


async def has_any_staff_permission(tg_id: int) -> bool:
    """Use one canonical server-side staff lookup instead of probing many permissions."""
    return bool((await staff_context(tg_id)).get("is_staff"))


async def has_staff_permission(tg_id: int, permission: str) -> bool:
    context = await staff_context(tg_id)
    permissions = set(context.get("permissions") or [])
    return "*" in permissions or permission in permissions


async def is_admin_mode(tg_id: int) -> bool:
    """Admin mode requires a live staff identity and the selected mode."""
    return bool((await staff_context(tg_id)).get("is_staff")) and (await get_mode(tg_id)) == ADMIN_MODE


async def ensure_mode(tg_id: int) -> str:
    """Resolve and persist the safe effective mode for this Telegram user."""
    stored = await get_mode(tg_id)
    context = await staff_context(tg_id)

    if stored == ADMIN_MODE:
        if context.get("is_staff"):
            return ADMIN_MODE
        await set_mode(tg_id, PARTICIPANT_MODE)
        return PARTICIPANT_MODE

    if stored == PARTICIPANT_MODE:
        return PARTICIPANT_MODE

    mode = ADMIN_MODE if context.get("is_staff") else PARTICIPANT_MODE
    await set_mode(tg_id, mode)
    return mode


async def require_admin_mode(message) -> bool:
    context = await staff_context(message.from_user.id)
    if not context.get("is_staff"):
        await message.answer("❌ Этот раздел доступен только персоналу PRISMA.")
        return False
    if (await get_mode(message.from_user.id)) != ADMIN_MODE:
        await message.answer("👤 Сейчас включён режим участника. Переключитесь в режим администратора.")
        return False
    return True


async def require_admin_mode_callback(callback) -> bool:
    context = await staff_context(callback.from_user.id)
    if not context.get("is_staff"):
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return False
    if (await get_mode(callback.from_user.id)) != ADMIN_MODE:
        await callback.answer("👤 Сейчас включён режим участника. Переключитесь в режим администратора.", show_alert=True)
        return False
    return True


async def get_application_status(tg_id: int) -> str:
    """Live status: NO_USER, NO_APPLICATION, PENDING, REJECTED, ACCEPTED, or ERROR."""
    result = await bot_get_profile(tg_id)
    if result.error or not isinstance(result.data, dict):
        return "ERROR"
    if result.data.get("error") == "USER_NOT_FOUND":
        return "NO_USER"
    return result.data.get("application_status") or "NO_APPLICATION"


async def is_approved(tg_id: int) -> bool:
    """True only once the applicant's whitelist application has been accepted."""
    return await get_application_status(tg_id) == "ACCEPTED"
