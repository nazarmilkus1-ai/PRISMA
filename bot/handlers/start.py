from html import escape
from aiogram import Router, types
from aiogram.filters import Command, CommandObject
from aiogram.fsm.context import FSMContext

from db.rpc import bot_get_user_status, bot_consume_login_code, bot_touch_user
from keyboards.inline import main_menu_before_apply, main_menu_pending, main_menu_approved
from utils.commands import set_user_commands
from utils.mode import ADMIN_MODE
from utils.permissions import ensure_mode, has_any_staff_permission


router = Router()


async def _touch_private(user: types.User):
    return await bot_touch_user(
        user.id,
        user.username or "",
        user.first_name or "",
        user.last_name or "",
        user.full_name,
        "PRIVATE",
    )


async def _send_status_menu(message: types.Message, status: str):
    tg_id = message.from_user.id
    mode = await ensure_mode(tg_id)
    await set_user_commands(message.bot, tg_id, admin=mode == ADMIN_MODE)

    if mode == ADMIN_MODE:
        from handlers.admin_panel import send_dashboard
        await send_dashboard(message)
        return

    show_admin_switch = await has_any_staff_permission(tg_id)
    if status in ("NO_USER", "NO_APPLICATION", "REJECTED"):
        await message.answer(
            "🌙 <b>PRISMA</b>\n\n"
            "Чтобы попасть на сервер, подайте заявку — это 7 коротких шагов, около минуты.",
            reply_markup=main_menu_before_apply(show_admin_switch=show_admin_switch),
            parse_mode="HTML",
        )
    elif status == "PENDING":
        await message.answer(
            "⏳ Ваша заявка уже находится на рассмотрении администрации.",
            reply_markup=main_menu_pending(show_admin_switch=show_admin_switch),
        )
    elif status == "ACCEPTED":
        await message.answer(
            "✅ Ваша заявка уже принята. Добро пожаловать на PRISMA! 🌙",
            reply_markup=main_menu_approved(show_admin_switch=show_admin_switch),
        )
    else:
        await message.answer("❌ Не удалось определить статус. Попробуйте ещё раз позже.")


@router.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext, command: CommandObject):
    await state.clear()

    # Panel login uses a random session token; onboarding deep-link uses the
    # fixed "onboarding" marker. Both still must respect the real user status.
    if command.args:
        if command.args.lower() in {"onboarding", "onboard"}:
            await _touch_private(message.from_user)
            status = await bot_get_user_status(message.from_user.id)
            if status == "ERROR":
                await message.answer("❌ Ошибка соединения с базой данных.")
                return
            await _send_status_menu(message, status)
            return
        from services.ai.ambient import intent_from_start
        invited = intent_from_start(command.args)
        if invited:
            # Invited from a group by PRISMA_AI: continue with it in private.
            await _touch_private(message.from_user)
            from handlers.ai import _answer
            await _answer(message, invited[1])
            return
        await handle_login_code(message, command.args)
        return

    await _touch_private(message.from_user)
    status = await bot_get_user_status(message.from_user.id)
    if status == "ERROR":
        await message.answer("❌ Ошибка соединения с базой данных.")
        return
    await _send_status_menu(message, status)


async def handle_login_code(message: types.Message, session_token: str):
    result = await bot_consume_login_code(session_token, message.from_user.id)
    if result.error:
        await message.answer("❌ Не удалось получить код входа. Попробуйте ещё раз позже.")
        return

    data = result.data if isinstance(result.data, dict) else {}
    error = data.get("error")
    if error == "SESSION_NOT_FOUND":
        await message.answer("❌ Ссылка для входа недействительна. Нажмите «Войти» в панели ещё раз.")
        return
    if error == "SESSION_EXPIRED":
        await message.answer("⏳ Ссылка для входа устарела. Запросите новую в панели.")
        return

    code = data.get("code")
    if not code:
        await message.answer("❌ Не удалось сгенерировать код. Попробуйте ещё раз позже.")
        return

    await message.answer(
        f"🔐 Код для входа в панель PRISMA: <b>{escape(str(code))}</b>\n"
        "Действителен 5 минут. Никому его не передавайте.",
        parse_mode="HTML",
    )
