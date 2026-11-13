from aiogram import Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from html import escape
from db.rpc import bot_change_minecraft_nick
from utils.permissions import DENIED_MESSAGE, is_approved
from fsm.states import LinkForm
from utils.helpers import validate_minecraft_nick

router=Router()

@router.message(Command("link"))
async def cmd_link(message: types.Message, state: FSMContext):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return
    await state.set_state(LinkForm.waiting_for_nick)
    await message.answer("🔗 Введите новый Minecraft-ник или /cancel.")

@router.message(Command("cancel"), StateFilter(LinkForm.waiting_for_nick))
async def cancel_link(message: types.Message, state: FSMContext):
    await state.clear(); await message.answer("❌ Изменение ника отменено.")

@router.message(StateFilter(LinkForm.waiting_for_nick))
async def process_link(message: types.Message, state: FSMContext):
    nick=(message.text or "").strip()
    if not await is_approved(message.from_user.id):
        await state.clear()
        await message.answer(DENIED_MESSAGE)
        return
    # The platform is not known here; the RPC re-checks the nick against the profile's platform.
    valid,error=validate_minecraft_nick(nick)
    if not valid: await message.answer(f"❌ {error}"); return

    result=await bot_change_minecraft_nick(message.from_user.id,nick)
    if result.error:
        error = str(result.error)
        messages = {
            "APPLICATION_NOT_ACCEPTED": "⏳ Изменение Minecraft-ника доступно только после одобрения заявки.",
            "MINECRAFT_NICK_TAKEN": "❌ Этот Minecraft-ник уже занят.",
            "USER_NOT_FOUND": "❌ Профиль не найден.",
            "INVALID_MINECRAFT_NICK": "❌ Ник не подходит для вашей платформы. Java: 3–16 символов (латиница, цифры, «_»). Bedrock: Gamertag до 15 символов, пробелы можно.",
        }
        await message.answer(messages.get(error, f"❌ Не удалось изменить ник: {escape(error)}"), parse_mode="HTML")
        return
    if isinstance(result.data,dict) and result.data.get("error"):
        error = str(result.data["error"])
        await message.answer(f"❌ {escape(error)}", parse_mode="HTML")
        return
    shown = result.data.get("minecraft_nick") if isinstance(result.data, dict) else None
    extra = f"\nНа сервере вы будете как <code>{escape(str(shown))}</code>." if shown and result.data.get("gamertag") else ""
    await message.answer(
        "✅ Minecraft-ник изменён. Вайтлист использует этот ник автоматически при следующем входе." + extra,
        parse_mode="HTML",
    )
    await state.clear()
