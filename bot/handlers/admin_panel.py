import asyncio
import logging
import types
from aiogram import types
from utils.validation import Validation

async def _home(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для входа в панель")
    if not valid:
        logger.warning("_home: invalid tg_id %s", tg_id)
        return ("❌ Неверный Telegram ID.", home_keyboard(types.InlineKeyboardMarkup(inline_keyboard=[])))
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)

async def _guard(callback: types.CallbackQuery, permission: str | None) -> bool:
    tg_id = callback.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для админ-панели")
    if not valid:
        logger.warning("_guard: invalid tg_id %s", tg_id)
        return False

async def admin_entry(tg_id: int) -> None:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для входа в панель")
    if not valid:
        logger.warning("admin_entry: invalid tg_id %s", tg_id)
        return

async def _home_old(tg_id: int) -> tuple[str, types.InlineKeyboardMarkup]:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для старого домашнего экрана")
    if not valid:
        logger.warning("_home_old: invalid tg_id %s", tg_id)
        return ("❌ Неверный Telegram ID.", home_keyboard(types.InlineKeyboardMarkup(inline_keyboard=[])))
    context = await staff_context(tg_id)
    perms = context.get("permissions") or []
    snap = await admin_dashboard.snapshot(tg_id, perms)
    return admin_dashboard.render_home(context.get("role"), perms, snap), home_keyboard(snap, perms, PANEL_URL)
