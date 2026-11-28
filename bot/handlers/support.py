from html import escape
from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext

from config import ADMIN_GROUP_ID
from db.rpc import (
    bot_create_support_request,
    bot_get_prisma_rating,
    bot_list_support_requests,
    bot_manage_support_request,
    bot_rate_prisma,
)
from fsm.states import SupportForm
from keyboards.inline import prisma_rating_keyboard
from utils.permissions import is_approved, require_admin_mode

router = Router()


async def _notify_admins(bot, message: types.Message, ticket_no: int, body: str):
    if not ADMIN_GROUP_ID:
        return
    user = message.from_user
    name = f"@{escape(user.username)}" if user.username else escape(user.full_name or "Пользователь")
    await bot.send_message(
        ADMIN_GROUP_ID,
        f"🆘 <b>Новое обращение в поддержку PRISMA</b>\n\n"
        f"Тикет: <b>#{ticket_no}</b>\n"
        f"Пользователь: {name} · <code>{user.id}</code>\n\n"
        f"{escape(body)}",
        parse_mode="HTML",
    )


@router.message(Command("support"))
async def support_command(message: types.Message, state: FSMContext):
    await state.set_state(SupportForm.waiting_message)
    await message.answer(
        "🆘 <b>Поддержка PRISMA</b>\n\n"
        "Опишите проблему одним сообщением (3–4000 символов).\n"
        "Зарегистрированный пользователь может обратиться до 2 раз в день, "
        "незарегистрированный — 1 раз.",
        parse_mode="HTML",
    )


@router.callback_query(F.data == "support")
async def support_callback(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    await state.set_state(SupportForm.waiting_message)
    if callback.message:
        await callback.message.answer(
            "🆘 <b>Поддержка PRISMA</b>\n\nОпишите проблему одним сообщением (3–4000 символов).",
            parse_mode="HTML",
        )


@router.message(StateFilter(SupportForm.waiting_message))
async def support_message(message: types.Message, state: FSMContext):
    body = (message.text or "").strip()
    if not 3 <= len(body) <= 4000:
        await message.answer("❌ Сообщение должно содержать от 3 до 4000 символов.")
        return

    result = await bot_create_support_request(message.from_user.id, body)
    data = result.data if isinstance(result.data, dict) else {}
    code = str(data.get("error") or result.error or "")

    if result.error or not data.get("success"):
        if code == "DAILY_LIMIT":
            await message.answer("⏳ Дневной лимит обращений уже использован.")
        elif code == "INVALID_MESSAGE":
            await message.answer("❌ Некорректное сообщение.")
        else:
            await message.answer("❌ Не удалось отправить обращение. Попробуйте позже.")
        await state.clear()
        return

    ticket_no = data.get("ticket_no")
    await state.clear()
    await message.answer(
        f"✅ Обращение <b>#{ticket_no}</b> отправлено администрации.\n"
        f"Осталось обращений сегодня: <b>{data.get('remaining', 0)}</b>.",
        parse_mode="HTML",
    )
    try:
        await _notify_admins(message.bot, message, ticket_no, body)
    except Exception:
        pass


@router.message(Command("rate_prisma"))
async def rate_prisma(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer("⏳ Оценка PRISMA доступна после одобрения заявки.")
        return
    result = await bot_get_prisma_rating(message.from_user.id)
    data = result.data if isinstance(result.data, dict) else {}
    await message.answer(
        f"💎 <b>Оценка PRISMA</b>\n\n"
        f"Ваша оценка: <b>{data.get('my_value') or 'не выставлена'}</b>\n"
        f"Средняя оценка сообщества: <b>{data.get('average', 0)}★</b>\n"
        f"Всего оценок: <b>{data.get('count', 0)}</b>",
        reply_markup=prisma_rating_keyboard(),
        parse_mode="HTML",
    )


@router.callback_query(F.data.startswith("prisma_rating:"))
async def rate_prisma_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Оценка PRISMA доступна после одобрения заявки.", show_alert=True)
        return
    try:
        value = int(callback.data.split(":", 1)[1])
    except Exception:
        await callback.answer("❌ Некорректная оценка.", show_alert=True)
        return
    result = await bot_rate_prisma(callback.from_user.id, value)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        await callback.answer("❌ Не удалось сохранить оценку.", show_alert=True)
        return
    await callback.answer(f"✅ Оценка PRISMA сохранена: {value}★")


@router.callback_query(F.data == "player:prisma_rating")
async def prisma_rating_button(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await rate_prisma(callback.message)


@router.message(Command("support_list"))
async def support_list(message: types.Message):
    if not await require_admin_mode(message):
        return
    result = await bot_list_support_requests(message.from_user.id, "OPEN", 30)
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        await message.answer("❌ Не удалось загрузить обращения.")
        return
    items = data.get("items") or []
    if not items:
        await message.answer("🆘 Открытых обращений нет.")
        return
    for item in items:
        username = item.get("telegram_username")
        author = f"@{escape(str(username))}" if username else f"TG <code>{item.get('telegram_id')}</code>"
        await message.answer(
            f"🆘 <b>#{item.get('ticket_no')}</b> · {escape(str(item.get('status')))}\n"
            f"{author}\n\n{escape(str(item.get('message') or ''))}",
            parse_mode="HTML",
        )


@router.message(Command("support_resolve"))
async def support_resolve(message: types.Message):
    if not await require_admin_mode(message):
        return
    parts = (message.text or "").split(maxsplit=1)
    if len(parts) != 2 or not parts[1].isdigit():
        await message.answer("❌ Использование: /support_resolve <номер тикета>")
        return
    result = await bot_manage_support_request(message.from_user.id, int(parts[1]), "RESOLVED")
    data = result.data if isinstance(result.data, dict) else {}
    if result.error or not data.get("success"):
        await message.answer("❌ Не удалось закрыть обращение.")
        return
    await message.answer(f"✅ Обращение #{parts[1]} закрыто.")
