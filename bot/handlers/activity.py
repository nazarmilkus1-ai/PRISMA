"""/activity — staff preview of the weekly activity check (nothing is applied); `/activity apply` runs it now."""
from aiogram import Router, types
from aiogram.filters import Command, CommandObject

from db.rpc import bot_check_admin_permission
from services import inactivity
from utils.permissions import is_admin_mode

router = Router(name="activity")


async def _allowed(tg_id: int) -> bool:
    if not await is_admin_mode(tg_id):
        return False
    result = await bot_check_admin_permission(tg_id, "punishment.warn")
    return not result.error and bool(result.data)


@router.message(Command("activity", "активность_недели"), lambda m: m.chat.type == "private")
async def activity(message: types.Message, command: CommandObject):
    if message.from_user is None or not await _allowed(message.from_user.id):
        await message.answer("Нужен режим админа и право выдавать предупреждения.")
        return
    apply = (command.args or "").strip().lower() == "apply"
    if apply and not inactivity.enabled():
        await message.answer("Автопроверка выключена (ACTIVITY_WARN не равно 1) — применять вручную тоже не буду. Предпросмотр: /activity")
        return
    text = await inactivity.run_check(message.bot, apply=apply)
    await message.answer(text + ("" if apply else "\n\n<i>Предпросмотр: ничего не применено. Применить сейчас: /activity apply</i>"), parse_mode="HTML")
