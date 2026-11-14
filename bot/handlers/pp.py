"""/pp — PRISMA Points balance, history, transfers; /pp give — staff correction."""
from __future__ import annotations

from html import escape

from aiogram import Router, types
from aiogram.filters import Command, CommandObject

from db.rpc import bot_check_admin_permission, bot_pp_adjust, bot_pp_history, bot_pp_transfer
from services import points
from utils.permissions import DENIED_MESSAGE, is_admin_mode, is_approved

router = Router(name="points")


@router.message(Command("pp", "points", "баланс"), lambda m: m.chat.type == "private")
async def cmd_pp(message: types.Message, command: CommandObject):
    uid = message.from_user.id
    if not await is_approved(uid):
        await message.answer(DENIED_MESSAGE)
        return
    args = (command.args or "").split()
    sub = args[0].lower() if args else ""

    if sub in {"send", "перевод", "отправить"}:
        amount = points.parse_amount(args[2]) if len(args) >= 3 else None
        if len(args) < 3 or amount is None:
            await message.answer("Формат: <code>/pp send @ник 50</code>", parse_mode="HTML")
            return
        result = await bot_pp_transfer(uid, args[1], amount)
        data = result.data if isinstance(result.data, dict) else {}
        if result.error or not data.get("success"):
            await message.answer("❌ " + points.error_text(data.get("error")))
            return
        await message.answer(
            f"✅ Переведено <b>{points.fmt(amount)} PP</b> → {escape(str(data.get('to') or args[1]))}.\n"
            f"Баланс: <b>{points.fmt(data.get('balance'))} PP</b>", parse_mode="HTML")
        return

    if sub in {"give", "выдать"}:
        allowed = await is_admin_mode(uid)
        if allowed:
            check = await bot_check_admin_permission(uid, "economy.manage")
            allowed = not check.error and bool(check.data)
        if not allowed:
            await message.answer("Нужен режим админа и право economy.manage.")
            return
        amount = points.parse_amount(args[2]) if len(args) >= 3 else None
        if len(args) < 3 or amount is None or amount == 0:
            await message.answer("Формат: <code>/pp give @ник +100 причина</code> (минус — списать).", parse_mode="HTML")
            return
        result = await bot_pp_adjust(uid, args[1], amount, " ".join(args[3:]) or None)
        data = result.data if isinstance(result.data, dict) else {}
        if result.error or not data.get("success"):
            await message.answer("❌ " + points.error_text(data.get("error")))
            return
        await message.answer(f"✅ Готово. Новый баланс игрока: <b>{points.fmt(data.get('balance'))} PP</b>", parse_mode="HTML")
        return

    result = await bot_pp_history(uid, 10)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        await message.answer("❌ " + points.error_text(data.get("error")))
        return
    await message.answer(points.render_history(data) + "\n\n" + points.HELP.split("\n", 1)[1].split("\n\n")[0], parse_mode="HTML")
