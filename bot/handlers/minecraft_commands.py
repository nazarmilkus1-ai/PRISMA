from aiogram import F, Router, types
from aiogram.filters import Command

from db.rpc import bot_get_minecraft_auth_status, bot_get_profile
from utils.minecraft_commands import render_catalog

router = Router()


async def _platform(tg_id: int) -> str | None:
    result = await bot_get_profile(tg_id)
    if result.error or not isinstance(result.data, dict):
        return None
    return str(result.data.get("platform") or "").upper() or None


@router.message(Command(commands={"commands", "mc_commands"}))
async def cmd_minecraft_commands(message: types.Message):
    platform = await _platform(message.from_user.id)
    await message.answer(render_catalog(platform), parse_mode="HTML")


@router.callback_query(F.data == "player:minecraft_commands")
async def callback_minecraft_commands(callback: types.CallbackQuery):
    await callback.answer()
    platform = await _platform(callback.from_user.id)
    if callback.message:
        await callback.message.answer(render_catalog(platform), parse_mode="HTML")



async def _auth_message(message: types.Message, tg_id: int):
    result = await bot_get_minecraft_auth_status(tg_id)
    if result.error or not isinstance(result.data, dict):
        await message.answer("❌ Состояние PRISMA Auth сейчас недоступно.")
        return

    data = result.data
    if data.get("error") == "USER_NOT_FOUND":
        await message.answer("⏳ Сначала откройте /start и завершите привязку аккаунта PRISMA.")
        return

    platform = str(data.get("platform") or "").upper()
    nickname = str(data.get("minecraft_nickname") or "—")
    if platform == "BEDROCK":
        await message.answer(
            "🧱 <b>Bedrock</b>\n\n"
            f"Minecraft: <code>{nickname}</code>\n"
            "Пароль PRISMA Auth не используется. Вход подтверждается через Geyser + Floodgate.",
            parse_mode="HTML",
        )
        return

    configured = bool(data.get("configured"))
    await message.answer(
        "🔐 <b>PRISMA Auth</b>\n\n"
        f"Minecraft: <code>{nickname}</code>\n"
        f"Java-пароль: <b>{'установлен' if configured else 'не установлен'}</b>\n\n"
        "Пароль задаётся или меняется в настройках участника на сайте PRISMA. "
        "В Minecraft вход выполняется командой <code>/login &lt;пароль&gt;</code>.",
        parse_mode="HTML",
    )


@router.message(Command(commands={"mc_auth", "auth_status"}))
async def cmd_minecraft_auth(message: types.Message):
    await _auth_message(message, message.from_user.id)


@router.callback_query(F.data == "player:mc_auth")
async def callback_minecraft_auth(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _auth_message(callback.message, callback.from_user.id)
