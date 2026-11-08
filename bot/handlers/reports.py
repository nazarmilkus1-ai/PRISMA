from aiogram import Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from db.rpc import bot_create_report, bot_find_user
from fsm.states import ReportForm
from config import ADMIN_GROUP_ID
from utils.permissions import DENIED_MESSAGE, is_approved
from html import escape

router=Router()

@router.message(Command("report"))
async def cmd_report(message: types.Message,state:FSMContext):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE); return
    args=(message.text or "").split(maxsplit=1)
    if len(args)==2:
        target=await bot_find_user(args[1])
        if target.error or not isinstance(target.data,dict) or target.data.get("error"):
            await message.answer("❌ Игрок не найден."); return
        await state.update_data(target_tg_id=target.data.get("tg_id"),target_label=args[1]); await state.set_state(ReportForm.waiting_reason)
        await message.answer("📢 Введите причину жалобы."); return
    await state.set_state(ReportForm.waiting_target); await message.answer("📢 Введите Minecraft-ник, @username или Telegram ID нарушителя.")

@router.message(StateFilter(ReportForm.waiting_target))
async def report_target(message:types.Message,state:FSMContext):
    identifier=(message.text or "").strip(); r=await bot_find_user(identifier)
    if r.error or not isinstance(r.data,dict) or r.data.get("error"):
        await message.answer("❌ Игрок не найден."); return
    await state.update_data(target_tg_id=r.data.get("tg_id"),target_label=identifier); await state.set_state(ReportForm.waiting_reason); await message.answer("📝 Введите причину жалобы.")

@router.message(StateFilter(ReportForm.waiting_reason))
async def report_reason(message:types.Message,state:FSMContext):
    reason=(message.text or "").strip()
    if not 3<=len(reason)<=2000: await message.answer("❌ Причина должна содержать 3–2000 символов."); return
    d=await state.get_data(); r=await bot_create_report(message.from_user.id,d["target_tg_id"],reason)
    if r.error or not isinstance(r.data,dict) or not r.data.get("success"):
        error = str(r.error or (r.data or {}).get("error") or r.data)
        messages = {
            "CANNOT_REPORT_SELF": "❌ Нельзя пожаловаться на самого себя.",
            "DUPLICATE_OPEN_REPORT": "⚠️ У вас уже есть открытая жалоба на этого игрока.",
            "USER_NOT_FOUND": "❌ Игрок не найден.",
            "INVALID_REASON": "❌ Некорректная причина жалобы.",
        }
        await message.answer(messages.get(error, f"❌ Не удалось создать жалобу: {escape(error)}"),parse_mode="HTML")
        return
    await state.clear(); await message.answer("✅ Жалоба передана администрации.")
    if ADMIN_GROUP_ID:
        try: await message.bot.send_message(ADMIN_GROUP_ID,f"📢 <b>Новая жалоба</b>\nНа: <code>{escape(str(d['target_label']))}</code>\nОт: <code>{message.from_user.id}</code>\nПричина: {escape(reason)}",parse_mode="HTML")
        except Exception: pass

@router.message(Command("cancel"),StateFilter(ReportForm))
async def cancel_report(message:types.Message,state:FSMContext):
    await state.clear(); await message.answer("❌ Жалоба отменена.")
