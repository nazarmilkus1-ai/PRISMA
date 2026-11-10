"""One-tap moderation actions on application / report / appeal cards.

Callback data: ``adm:<kind>:<action>:<uuid>``  (kinds: app, rep, apl).
Destructive actions need a second tap ("!" suffix) so a stray tap does nothing.
"""
from aiogram import F, Router, types
from aiogram.types import InlineKeyboardMarkup

from db.rpc import bot_approve_application, bot_manage_appeal, bot_manage_support_request, bot_reject_application, bot_set_report_status
from handlers.admin import require_callback_perm
from keyboards.admin_actions import _btn, application_actions, appeal_actions, report_actions, support_actions

router = Router(name="admin_actions")


_ORIGINAL = {"app": application_actions, "rep": report_actions, "apl": appeal_actions, "sup": support_actions}
# action -> (permission, human label, needs confirmation)
_RULES = {
    ("app", "ok"): ("application.approve", "✅ Заявка одобрена", False),
    ("app", "no"): ("application.reject", "❌ Заявка отклонена", True),
    ("rep", "rev"): ("report.assign", "👀 Репорт взят в работу", False),
    ("rep", "res"): ("report.resolve", "✅ Репорт решён", False),
    ("rep", "dis"): ("report.reject", "🚫 Репорт отклонён", True),
    ("apl", "rev"): ("appeal.manage", "👀 Апелляция взята в работу", False),
    ("apl", "ok"): ("appeal.manage", "✅ Апелляция одобрена, наказание снято", True),
    ("sup", "res"): ("player.view", "✅ Обращение закрыто", False),
    ("apl", "no"): ("appeal.manage", "❌ Апелляция отклонена", True),
}
_ERRORS = {
    "REPORT_NOT_FOUND": "Репорт не найден.",
    "REPORT_ALREADY_CLOSED": "Репорт уже закрыт.",
    "APPEAL_NOT_FOUND": "Апелляция не найдена.",
    "APPEAL_ALREADY_CLOSED": "Апелляция уже закрыта.",
    "PERMISSION_DENIED": "Недостаточно прав.",
    "ADMIN_LACKS_PERMISSION": "Недостаточно прав.",
}


async def _execute(kind: str, action: str, uid: str, admin_id: int):
    if kind == "app":
        fn = bot_approve_application(uid, admin_id) if action == "ok" else bot_reject_application(uid, admin_id, None)
    elif kind == "rep":
        status = {"rev": "IN_REVIEW", "res": "RESOLVED", "dis": "DISMISSED"}[action]
        fn = bot_set_report_status(uid, status, admin_id)
    elif kind == "sup":
        fn = bot_manage_support_request(admin_id, int(uid), "RESOLVED")
    else:
        name = {"rev": "REVIEW", "ok": "APPROVE", "no": "REJECT"}[action]
        fn = bot_manage_appeal(uid, name, admin_id, None)
    return await fn


@router.callback_query(F.data.startswith("adm:"))
async def admin_action(callback: types.CallbackQuery):
    parts = (callback.data or "").split(":")
    if len(parts) != 4 or parts[1] not in _ORIGINAL:
        await callback.answer("Некорректная кнопка.", show_alert=True)
        return
    _, kind, action, uid = parts
    if kind == "sup" and not uid.isdigit():
        await callback.answer("Некорректная кнопка.", show_alert=True)
        return
    confirm = action.endswith("!")
    action = action.rstrip("!")

    if action == "back":
        await callback.answer()
        if callback.message:
            await callback.message.edit_reply_markup(reply_markup=_ORIGINAL[kind](uid))
        return

    rule = _RULES.get((kind, action))
    if not rule:
        await callback.answer("Некорректная кнопка.", show_alert=True)
        return
    permission, done_text, needs_confirm = rule
    if not await require_callback_perm(callback, permission):
        return

    if needs_confirm and not confirm:
        await callback.answer()
        if callback.message:
            await callback.message.edit_reply_markup(reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                _btn("⚠️ Да, подтвердить", kind, f"{action}!", uid),
                _btn("↩️ Отмена", kind, "back", uid),
            ]]))
        return

    result = await _execute(kind, action, uid, callback.from_user.id)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        error = str(result.error or data.get("error") or "")
        await callback.answer("❌ " + _ERRORS.get(error, "Не удалось выполнить действие."), show_alert=True)
        return

    await callback.answer(done_text)
    if callback.message:
        who = callback.from_user.full_name
        try:
            await callback.message.edit_text(
                f"{callback.message.html_text}\n\n{done_text} — {who}",
                parse_mode="HTML",
                reply_markup=None,
            )
        except Exception:
            await callback.message.edit_reply_markup(reply_markup=None)
