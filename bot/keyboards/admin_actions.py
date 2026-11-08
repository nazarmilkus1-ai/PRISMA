"""Inline keyboards for one-tap moderation actions (see handlers/admin_actions.py)."""
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup


def _btn(text: str, kind: str, action: str, uid: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(text=text, callback_data=f"adm:{kind}:{action}:{uid}")


def application_actions(uid: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[[_btn("✅ Одобрить", "app", "ok", uid), _btn("❌ Отклонить", "app", "no", uid)]])


def report_actions(uid: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [_btn("👀 В работу", "rep", "rev", uid), _btn("✅ Решено", "rep", "res", uid)],
        [_btn("🚫 Отклонить", "rep", "dis", uid)],
    ])


def appeal_actions(uid: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [_btn("👀 В работу", "apl", "rev", uid)],
        [_btn("✅ Одобрить (снять наказание)", "apl", "ok", uid)],
        [_btn("❌ Отклонить", "apl", "no", uid)],
    ])
