import re
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.types import BufferedInputFile

from db.rpc import bot_get_profile, bot_get_user_status
from fsm.states import AskForm
from handlers.guide import build_guide
from db.rpc import bot_check_admin_permission, bot_list_current_participants, bot_list_inactive_members
from services.ai import navigator
from services.ai.admin_tools import run_copilot
from services.ai.bench import run_bench
from services.ai.client import AIError, is_configured
from utils.permissions import has_any_staff_permission, require_admin_mode
from utils.rules import rules_text

router = Router(name="ai")


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")


async def _answer(message: types.Message, question: str):
    question = (question or "").strip()
    if len(question) < 2:
        await message.answer("Напишите вопрос чуть подробнее.")
        return
    tg_id = message.from_user.id
    kind = navigator.fast_kind(question)

    # Code-first: deterministic answers, no model call and no database lookup needed.
    if kind == "rules":
        await message.answer(rules_text(), parse_mode="HTML")
        return
    status = await _status_for_intent(tg_id, kind)
    if kind in {"guide", "apply"}:
        profile: dict = {}
        if status == "ACCEPTED":
            result = await bot_get_profile(tg_id)
            if not result.error and isinstance(result.data, dict) and not result.data.get("error"):
                profile = result.data
        text, markup = build_guide(status, profile)
        await message.answer(text, parse_mode="HTML", reply_markup=markup)
        return

    if not is_configured("user"):
        await message.answer("🤖 Помощник пока не подключён. Используйте /help или /support.")
        return
    if not navigator.allowed(tg_id):
        await message.answer("⏳ Слишком много вопросов подряд. Попробуйте чуть позже.")
        return
    waiting = await message.answer("🤖 Думаю…")
    try:
        text = await navigator.ask_model(question, status)
    except AIError:
        text = "😕 Не получилось ответить. Попробуйте переформулировать или откройте /help."
    try:
        await waiting.edit_text(text)  # plain text: model output is never parsed as HTML
    except Exception:
        await message.answer(text)


@router.message(Command("ask", "спросить"), F.chat.type == "private")
async def ask_command(message: types.Message, command: CommandObject, state: FSMContext):
    if command.args:
        await state.clear()
        await _answer(message, command.args)
        return
    await state.set_state(AskForm.waiting)
    await message.answer("🤖 Что подсказать? Напишите вопрос одним сообщением (или /cancel).")


@router.callback_query(F.data == "ask")
async def ask_button(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await state.set_state(AskForm.waiting)
        await callback.message.answer("🤖 Что подсказать? Напишите вопрос одним сообщением (или /cancel).")


@router.message(Command("cancel"), StateFilter(AskForm.waiting))
async def ask_cancel(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("Ок, отменено. /start")


@router.message(StateFilter(AskForm.waiting), F.text, ~F.text.startswith("/"))
async def ask_waiting(message: types.Message, state: FSMContext):
    await state.clear()
    await _answer(message, message.text)


@router.message(Command("ai_bench"), F.chat.type == "private")
async def ai_bench(message: types.Message):
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    if not is_configured("user"):
        await message.answer("AI не настроен: задайте AI_API_KEY_USER.")
        return
    await message.answer("🧪 Запускаю бенчмарк моделей, это займёт до пары минут…")
    await message.answer(await run_bench(), parse_mode="HTML")


# ---------------------------------------------------------------- admin Copilot

_PLAYERS_RE = re.compile(r"(список|все|всех|выведи|покажи|склади|составь).*(игрок|участник|ник|юз|username|юзернейм)|^(ники|юзы)$", re.I)
_INACTIVE_RE = re.compile(r"неактив", re.I)


def _days_from_text(text: str) -> int:
    if re.search(r"месяц|month", text, re.I):
        return 30
    if re.search(r"недел|week", text, re.I):
        return 7
    match = re.search(r"\d+", text)
    return max(1, min(30, int(match.group()))) if match else 7


async def _send_long(message: types.Message, title: str, lines: list[str], filename: str):
    """Chunk by Telegram's limit; very long lists go out as a text file instead."""
    body = "\n".join(lines)
    if len(lines) > 120:
        await message.answer(f"{title} — {len(lines)} шт. Список файлом ⬇️", parse_mode="HTML")
        plain = re.sub(r"<[^>]+>", "", body)
        await message.answer_document(BufferedInputFile(plain.encode("utf-8"), filename=filename))
        return
    chunk = title
    for line in lines:
        if len(chunk) + len(line) + 1 > 3800:
            await message.answer(chunk, parse_mode="HTML")
            chunk = ""
        chunk += ("\n" if chunk else "") + line
    await message.answer(chunk, parse_mode="HTML")


async def _players_report(message: types.Message):
    result = await bot_list_current_participants()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список участников.")
        return
    if not result.data:
        await message.answer("ℹ️ Участников пока нет.")
        return
    lines = []
    for index, row in enumerate(result.data, 1):
        name = escape(str(row.get("display_name") or "—"))
        username = row.get("username")
        user = f"@{escape(str(username))}" if username else "—"
        lines.append(f"{index}. {name} · {user} · <code>{escape(str(row.get('nickname') or '—'))}</code>")
    await _send_long(message, f"👥 <b>Участники PRISMA ({len(lines)})</b>\nИмя · Telegram · Minecraft", lines, "prisma_players.txt")


async def _inactive_report(message: types.Message, days: int):
    result = await bot_list_inactive_members(days, 100)
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список неактивных.")
        return
    if not result.data:
        await message.answer(f"✅ Неактивных больше {days} дн. нет.")
        return
    lines = []
    for index, row in enumerate(result.data, 1):
        name = escape(str(row.get("display_name") or row.get("username") or row.get("telegram_id") or "—"))
        username = f" @{escape(str(row['username']))}" if row.get("username") else ""
        lines.append(f"{index}. {name}{username}")
    await _send_long(message, f"✖️ <b>Неактивны больше {days} дн. ({len(lines)})</b>", lines, "prisma_inactive.txt")


async def _copilot(message: types.Message, request: str):
    request = (request or "").strip()
    if len(request) < 2:
        await message.answer("Напишите, что нужно, например: «список игроков и их юзы».")
        return
    admin_id = message.from_user.id

    # Code-first: the common read requests need no model at all.
    if _INACTIVE_RE.search(request):
        if await _has(admin_id, "player.view"):
            await _inactive_report(message, _days_from_text(request))
        else:
            await message.answer("❌ Недостаточно прав.")
        return
    if _PLAYERS_RE.search(request):
        if await _has(admin_id, "player.view"):
            await _players_report(message)
        else:
            await message.answer("❌ Недостаточно прав.")
        return

    if not is_configured("admin"):
        await message.answer("🤖 Copilot не настроен: задайте AI_API_KEY_ADMIN.")
        return
    waiting = await message.answer("🤖 Работаю…")
    try:
        text, cards = await run_copilot(admin_id, request)
    except AIError:
        await waiting.edit_text("😕 Не получилось выполнить запрос. Попробуйте проще, например: «заявки» или «неактив 14».")
        return
    try:
        await waiting.edit_text(text)
    except Exception:
        await message.answer(text)
    for card_text, markup in cards:
        await message.answer(card_text, parse_mode="HTML", reply_markup=markup)


async def _has(admin_id: int, permission: str) -> bool:
    result = await bot_check_admin_permission(admin_id, permission)
    return not result.error and bool(result.data)


@router.message(Command("ai", "copilot"), F.chat.type == "private")
async def copilot_command(message: types.Message, command: CommandObject, state: FSMContext):
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    if command.args:
        await state.clear()
        await _copilot(message, command.args)
        return
    await state.set_state(AskForm.admin_waiting)
    await message.answer(
        "🤖 <b>Copilot</b>\nНапишите задачу, например:\n• список игроков и их юзы\n• кто неактивен месяц\n• какие заявки ждут\n"
        "Изменения — только через кнопки подтверждения. /cancel — выйти.",
        parse_mode="HTML",
    )


@router.callback_query(F.data == "ai:admin")
async def copilot_button(callback: types.CallbackQuery, state: FSMContext):
    if not await has_any_staff_permission(callback.from_user.id):
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return
    await callback.answer()
    if callback.message:
        await state.set_state(AskForm.admin_waiting)
        await callback.message.answer("🤖 Copilot: напишите задачу (например «список игроков и их юзы»). /cancel — выйти.")


@router.message(Command("cancel"), StateFilter(AskForm.admin_waiting))
async def copilot_cancel(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("Ок, Copilot закрыт.")


@router.message(StateFilter(AskForm.admin_waiting), F.text, ~F.text.startswith("/"))
async def copilot_waiting(message: types.Message, state: FSMContext):
    await state.clear()
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    await _copilot(message, message.text)
