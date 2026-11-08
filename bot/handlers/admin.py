from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command

from config import MODERATION_GROUP_ID, PANEL_URL
from db.admin import (
    find_players,
    open_appeals,
    open_reports,
    pending_applications,
)
from db.player import _user
from db.rpc import (
    bot_approve_application,
    bot_check_admin_permission,
    bot_get_automod_config,
    bot_get_pending_count,
    bot_get_server_status,
    bot_reject_application,
    bot_set_report_status,
    bot_manage_appeal,
)
from keyboards.inline import admin_menu
from keyboards.admin_actions import application_actions, appeal_actions, report_actions
from utils.errors import safe_rpc_error
from utils.permissions import require_admin_mode, require_admin_mode_callback

router = Router()

async def require_perm(message: types.Message, permission: str) -> bool:
    if not await require_admin_mode(message):
        return False
    result = await bot_check_admin_permission(message.from_user.id, permission)
    if result.error or not result.data:
        await message.answer("❌ Недостаточно прав.")
        return False
    return True


@router.message(Command("admin"))
async def admin_command(message: types.Message):
    if not await require_admin_mode(message):
        return
    await message.answer(
        "🛡 <b>PRISMA STAFF</b>\n\nВыберите раздел управления.",
        reply_markup=admin_menu(PANEL_URL),
        parse_mode="HTML",
    )


@router.callback_query(F.data == "admin:applications")
async def admin_applications(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "application.view"):
        return
    await callback.answer()
    rows, err = await pending_applications(callback.from_user.id)
    if err:
        await callback.message.answer("❌ Не удалось загрузить заявки.")
        return
    if not rows:
        await callback.message.answer("📋 Ожидающих заявок нет.")
        return
    for row in rows:
        text = (
            f"📋 <b>Заявка #{escape(str(row.get('application_no') or '—'))}</b>\n"
            f"Имя: {escape(str(row.get('full_name') or '—'))}\n"
            f"Minecraft: <code>{escape(str(row.get('nickname') or '—'))}</code>\n"
            f"Платформа: {escape(str(row.get('platform') or '—'))}\n"
            f"Возраст: {row.get('age') or '—'}\n"
            f"Создана: <code>{escape(str(row.get('created_at') or ''))}</code>"
        )
        await callback.message.answer(text, parse_mode="HTML", reply_markup=application_actions(str(row["id"])))


@router.message(Command("app_approve"))
async def app_approve(message: types.Message):
    if not await require_perm(message, "application.approve"):
        return
    args = (message.text or "").split()
    if len(args) != 2:
        await message.answer("❌ Использование: /app_approve <application_uuid>")
        return
    result = await bot_approve_application(args[1], message.from_user.id)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        await message.answer(f"❌ {safe_rpc_error(result, 'Не удалось одобрить заявку.')}", parse_mode="HTML")
        return
    await message.answer("✅ Заявка одобрена.")


@router.message(Command("app_reject"))
async def app_reject(message: types.Message):
    if not await require_perm(message, "application.reject"):
        return
    args = (message.text or "").split(maxsplit=2)
    if len(args) < 2:
        await message.answer("❌ Использование: /app_reject <application_uuid> [причина]")
        return
    reason = args[2] if len(args) == 3 else None
    result = await bot_reject_application(args[1], message.from_user.id, reason)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        await message.answer(f"❌ {safe_rpc_error(result, 'Не удалось отклонить заявку.')}", parse_mode="HTML")
        return
    await message.answer("✅ Заявка отклонена.")


@router.callback_query(F.data == "admin:reports")
async def admin_reports(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "report.view"):
        return
    await callback.answer()
    rows, err = await open_reports(callback.from_user.id)
    if err:
        await callback.message.answer("❌ Не удалось загрузить репорты.")
        return
    if not rows:
        await callback.message.answer("📢 Открытых репортов нет.")
        return
    for row in rows:
        await callback.message.answer(
            f"📢 <b>Репорт #{escape(str(row.get('ticket_no') or row['id']))}</b>\n"
            f"Категория: {escape(str(row.get('category') or row.get('type') or '—'))}\n"
            f"На: <code>{escape(str(row.get('target_nickname') or '—'))}</code>\n"
            f"Приоритет: <b>{escape(str(row.get('priority') or 'NORMAL'))}</b>\n"
            f"Статус: <b>{escape(str(row.get('status') or 'OPEN'))}</b>\n"
            f"{escape(str(row.get('description') or ''))}",
            parse_mode="HTML",
            reply_markup=report_actions(str(row["id"])),
        )


async def require_callback_perm(callback: types.CallbackQuery, permission: str) -> bool:
    if not await require_admin_mode_callback(callback):
        return False
    result = await bot_check_admin_permission(callback.from_user.id, permission)
    if result.error or not result.data:
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return False
    return True


@router.message(Command("report_status"))
async def report_status(message: types.Message):
    args = (message.text or "").split()
    if len(args) != 3:
        await message.answer("❌ Использование: /report_status <report_uuid> <IN_REVIEW|RESOLVED|DISMISSED>")
        return
    status = args[2].upper()
    if status == "IN_REVIEW":
        perm = "report.assign"
    elif status == "RESOLVED":
        perm = "report.resolve"
    elif status == "DISMISSED":
        perm = "report.reject"
    else:
        await message.answer("❌ Неизвестный статус.")
        return
    if not await require_perm(message, perm):
        return
    result = await bot_set_report_status(args[1], status, message.from_user.id)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        error = str(result.error or (result.data or {}).get("error") or result.data)
        messages = {
            "ADMIN_LACKS_PERMISSION": "❌ Недостаточно прав.",
            "REPORT_NOT_FOUND": "❌ Репорт не найден.",
            "REPORT_ALREADY_CLOSED": "⚠️ Репорт уже закрыт.",
            "INVALID_REPORT_STATUS": "❌ Неизвестный статус.",
        }
        await message.answer(messages.get(error, "❌ Не удалось обновить репорт."))
        return
    await message.answer("✅ Репорт обновлён.")


@router.callback_query(F.data == "admin:appeals")
async def admin_appeals(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "appeal.view"):
        return
    await callback.answer()
    rows, err = await open_appeals(callback.from_user.id)
    if err:
        await callback.message.answer("❌ Не удалось загрузить апелляции.")
        return
    if not rows:
        await callback.message.answer("⚖️ Открытых апелляций нет.")
        return
    for row in rows:
        await callback.message.answer(
            f"⚖️ <b>Апелляция</b> <code>{row['id']}</code>\n"
            f"Игрок: <code>{row.get('telegram_id')}</code>\n"
            f"Наказание: <code>{row.get('punishment_id') or '—'}</code>\n"
            f"Статус: <b>{escape(str(row.get('status') or 'OPEN'))}</b>\n"
            f"{escape(str(row.get('reason') or ''))}",
            parse_mode="HTML",
            reply_markup=appeal_actions(str(row["id"])),
        )


async def _finish_appeal(message: types.Message, status: str):
    if not await require_perm(message, "appeal.manage"):
        return

    args = (message.text or "").split(maxsplit=2)
    if len(args) < 2:
        command = "approve" if status == "APPROVED" else "reject"
        await message.answer(f"❌ Использование: /appeal_{command} <uuid> [заметка]")
        return

    action = "APPROVE" if status == "APPROVED" else "REJECT"
    note = args[2] if len(args) == 3 else None
    result = await bot_manage_appeal(args[1], action, message.from_user.id, note)

    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        error = str(result.error or result.data)
        messages = {
            "PERMISSION_DENIED": "❌ Недостаточно прав.",
            "APPEAL_NOT_FOUND": "❌ Апелляция не найдена.",
            "APPEAL_ALREADY_CLOSED": "⚠️ Апелляция уже закрыта.",
            "UNKNOWN_ACTION": "❌ Неизвестное действие.",
            "USER_NOT_FOUND": "❌ Игрок не найден.",
        }
        await message.answer(messages.get(error, f"❌ {safe_rpc_error(result, 'Не удалось обработать апелляцию.')}"), parse_mode="HTML")
        return

    await message.answer("✅ Апелляция одобрена и наказание снято." if action == "APPROVE" else "✅ Апелляция отклонена.")


@router.message(Command("appeal_review"))
async def appeal_review(message: types.Message):
    if not await require_perm(message, "appeal.manage"):
        return

    args = (message.text or "").split(maxsplit=2)
    if len(args) < 2:
        await message.answer("❌ Использование: /appeal_review <uuid> [заметка]")
        return

    note = args[2] if len(args) == 3 else None
    result = await bot_manage_appeal(args[1], "REVIEW", message.from_user.id, note)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        error = str(result.error or result.data)
        messages = {
            "PERMISSION_DENIED": "❌ Недостаточно прав.",
            "APPEAL_NOT_FOUND": "❌ Апелляция не найдена.",
            "APPEAL_ALREADY_CLOSED": "⚠️ Апелляция уже закрыта.",
            "UNKNOWN_ACTION": "❌ Неизвестное действие.",
        }
        await message.answer(messages.get(error, f"❌ {safe_rpc_error(result, 'Не удалось взять апелляцию в работу.')}"), parse_mode="HTML")
        return

    await message.answer("👀 Апелляция взята в работу.")

@router.message(Command("appeal_approve"))
async def appeal_approve(message: types.Message):
    await _finish_appeal(message, "APPROVED")


@router.message(Command("appeal_reject"))
async def appeal_reject(message: types.Message):
    await _finish_appeal(message, "REJECTED")


@router.callback_query(F.data == "admin:automod")
async def admin_automod(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "automod.view"):
        return
    await callback.answer()
    result = await bot_get_automod_config(MODERATION_GROUP_ID)
    if result.error:
        await callback.message.answer("❌ Не удалось получить конфигурацию автомода.")
        return
    data = result.data if isinstance(result.data, dict) else {}
    settings = data.get("settings") or {}
    await callback.message.answer(
        "🤖 <b>AUTOMOD</b>\n\n"
        f"Чат: <code>{MODERATION_GROUP_ID}</code>\n"
        f"Профанация: {'✅' if settings.get('anti_profanity') else '❌'}\n"
        f"Капс: {'✅' if settings.get('anti_caps') else '❌'} ({settings.get('caps_threshold', '—')}%)\n"
        f"Флуд: {'✅' if settings.get('anti_flood') else '❌'} ({settings.get('flood_messages', '—')} за {settings.get('flood_window_seconds', '—')}с)\n"
        f"Ссылки: {'✅' if settings.get('anti_links') else '❌'}\n"
        f"Медиа: {'✅' if settings.get('anti_media') else '❌'}\n"
        f"Упоминания: {'✅' if settings.get('anti_mentions') else '❌'}",
        parse_mode="HTML",
    )


@router.callback_query(F.data == "admin:server")
async def admin_server(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "system.health"):
        return
    await callback.answer()
    r = await bot_get_server_status()
    data = r.data if not r.error and isinstance(r.data, dict) else {}
    await callback.message.answer(
        f"🖥 <b>Состояние сервера</b>\n\nСтатус: <b>{escape(str(data.get('status') or 'unknown'))}</b>\n"
        f"Нод: {data.get('online_nodes', 0)}/{data.get('total_nodes', 0)}",
        parse_mode="HTML",
    )


@router.callback_query(F.data == "admin:players")
async def admin_players(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "player.view"):
        return
    await callback.answer()
    await callback.message.answer("👥 Поиск игрока: /players <ник или username>")


@router.message(Command("players"))
async def players(message: types.Message):
    if not await require_perm(message, "player.view"):
        return
    args = (message.text or "").split(maxsplit=1)
    if len(args) != 2:
        await message.answer("❌ Использование: /players <ник/@username>")
        return
    rows, err = await find_players(message.from_user.id, args[1])
    if err:
        await message.answer("❌ Не удалось выполнить поиск.")
        return
    if not rows:
        await message.answer("👥 Игроки не найдены.")
        return
    for row in rows:
        await message.answer(
            f"👤 <b>{escape(str(row.get('minecraft_nickname') or row.get('telegram_username') or 'Игрок'))}</b>\n"
            f"Telegram: <code>{row.get('telegram_id')}</code>\n"
            f"Статус: {escape(str(row.get('status') or '—'))}\n"
            f"Whitelist: {'✅' if row.get('is_whitelisted') else '❌'}\n"
            f"Рейтинг: {row.get('rating', 0)}\nАктивность: {row.get('activity_score', 0)}\n"
            f"Уровень / XP: {row.get('level', 1)} / {row.get('xp', 0)}",
            parse_mode="HTML",
        )


@router.callback_query(F.data == "admin:moderation")
async def admin_moderation(callback: types.CallbackQuery):
    if not await require_callback_perm(callback, "punishment.view_history"):
        return
    await callback.answer()
    await callback.message.answer(
        "🛡 Модерация\n\n"
        "/warn <игрок> <причина>\n"
        "/mute <игрок> <причина> [10m]\n"
        "/ban <игрок> <причина> [1h]\n"
        "/kick <игрок> <причина>\n"
        "/history <игрок>",
    )
