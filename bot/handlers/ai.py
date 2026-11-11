import logging
import os
import re
import time
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.dispatcher.event.bases import SkipHandler
from aiogram.types import BufferedInputFile, InlineKeyboardMarkup

from db.rpc import bot_get_profile, bot_get_user_status
from fsm.states import AskForm
from handlers.guide import build_guide
from db.rpc import bot_check_admin_permission, bot_list_current_participants, bot_list_inactive_members
from services.ai import memory as ai_memory
from services.ai import navigator, sections
from services.ai.admin_tools import run_copilot
from services.ai.bench import run_bench
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.links import link_buttons
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from services.ai.live import live_answer, live_intent
from services.ai.players import apply_player_filter, parse_player_filter
from utils.mdhtml import strip_markdown, to_telegram_html
from utils.permissions import get_application_status, has_any_staff_permission, is_admin_mode, require_admin_mode
from utils.rules import rules_text

router = Router(name="ai")
# Free-text questions in private chat; registered last so every dialog with its own state wins.
free_router = Router(name="ai_free")
logger = logging.getLogger(__name__)


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")


async def _fallback_menu(message: types.Message, text: str):
    """Never leave a member with a dead end: show the real menu for their status."""
    from handlers.menu import _menu_for  # local import: menu imports this package's neighbours

    await message.answer(text, reply_markup=await _menu_for(message.from_user.id))


def _is_short(question: str) -> bool:
    return len(question.split()) <= 6


async def _answer(message: types.Message, question: str, private: bool = True):
    question = (question or "").strip()
    if len(question) < 2:
        await message.answer("Напишите вопрос чуть подробнее.")
        return
    tg_id = message.from_user.id
    kind = navigator.fast_kind(question)

    # Code-first: deterministic answers, no model call and no database lookup needed.
    if kind is None and live_intent(question):
        accepted = str(await bot_get_user_status(tg_id) or "") == "ACCEPTED"
        live = await live_answer(question, tg_id, accepted, private)
        if live:
            await message.answer(live, parse_mode="HTML")
            return
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

    configured = is_configured("user")
    matched = sections.match_sections(question)
    # A short question that names a section is answered by code; longer ones go to the model (with the buttons attached).
    if matched and (not configured or _is_short(question)):
        status = str(await bot_get_user_status(tg_id) or "")
        built = sections.build_answer(question, status)
        if built:
            await message.answer(built[0], reply_markup=built[1])
            return

    if not configured:
        await _fallback_menu(message, "🤖 PRISMA_AI пока не подключён, но вот куда можно нажать:")
        return
    if not navigator.allowed(tg_id):
        await message.answer("⏳ Слишком много вопросов подряд. Попробуйте чуть позже.")
        return
    status = str(await bot_get_user_status(tg_id) or "")
    waiting = await message.answer("🤖 PRISMA_AI думает…")
    markup = None
    if matched:
        built = sections.build_answer(question, status)
        markup = built[1] if built else None
    chat_id = message.chat.id
    try:
        text, cards = await run_member(tg_id, question, status, ai_memory.history(chat_id, tg_id), private)
    except AIError as exc:
        logger.warning("navigator model failed: %s", exc)
        try:
            await waiting.delete()
        except Exception:
            pass
        built = sections.build_answer(question, status) if matched else None
        if built:
            await message.answer(built[0], reply_markup=built[1])
        else:
            await _fallback_menu(message, "😕 Не получилось ответить. Выберите нужный раздел:")
        return
    ai_memory.remember(chat_id, tg_id, "user", question)
    ai_memory.remember(chat_id, tg_id, "assistant", text)
    rows = list(markup.inline_keyboard) if markup else []
    link_row = link_buttons(question, text)
    rows += [link_row[i:i + 2] for i in range(0, len(link_row), 2)]
    await _send_model_text(waiting, message, text, InlineKeyboardMarkup(inline_keyboard=rows) if rows else None)
    for card_text, card_markup in cards:
        await message.answer(card_text, parse_mode="HTML", reply_markup=card_markup)



async def _send_model_text(waiting, message, text, markup):
    """Model text is converted to escaped Telegram HTML; plain text is the fallback."""
    try:
        await waiting.edit_text(to_telegram_html(text), parse_mode="HTML", reply_markup=markup)
        return
    except Exception:
        pass
    plain = strip_markdown(text)
    try:
        await waiting.edit_text(plain, reply_markup=markup)
    except Exception:
        await message.answer(plain, reply_markup=markup)


@router.message(Command("ask", "спросить"), F.chat.type == "private")
async def ask_command(message: types.Message, command: CommandObject, state: FSMContext):
    if command.args:
        await state.clear()
        await _answer(message, command.args)
        return
    await state.set_state(AskForm.waiting)
    await message.answer("🤖 PRISMA_AI: что подсказать? Напишите вопрос одним сообщением (или /cancel).")


@router.callback_query(F.data == "ask")
async def ask_button(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.message:
        await state.set_state(AskForm.waiting)
        await callback.message.answer("🤖 PRISMA_AI: что подсказать? Напишите вопрос одним сообщением (или /cancel).")


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


@free_router.message(StateFilter(None), F.text, ~F.text.startswith("/"))
async def free_text(message: types.Message):
    text = (message.text or "").strip()
    if len(text) < 3 or message.from_user is None:
        return
    # Staff in admin mode talk to the PRISMA_AI, everyone else to the navigator.
    if await is_admin_mode(message.from_user.id):
        await _copilot(message, text)
        return
    await _answer(message, text)


@router.message(Command("ai_status"), F.chat.type == "private")
async def ai_status(message: types.Message):
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    host = re.sub(r"^https?://", "", base_url()).split("/")[0]
    lines = [f"🔌 <b>ИИ-шлюз</b>: <code>{escape(host)}</code>"]
    checks = (("пользователи", "user", model_for("user")), ("админы", "admin", model_for("admin")),
              ("запасная модель", "user", fallback_model()))
    for title, role, model in checks:
        if not is_configured(role):
            lines.append(f"• {title}: ключ не задан")
            continue
        started = time.monotonic()
        try:
            await chat([{"role": "user", "content": "Ответь одним словом: ок"}], role=role, model=model, max_tokens=600, timeout=45)
            lines.append(f"• {title}: ✅ <code>{escape(model)}</code> · {int((time.monotonic() - started) * 1000)} мс")
        except AIError as exc:
            lines.append(f"• {title}: ❌ <code>{escape(model)}</code> — {escape(str(exc))}")
    await message.answer("\n".join(lines), parse_mode="HTML")


# ---------------------------------------------------------------- admin PRISMA_AI

_PLAYERS_RE = re.compile(r"(список|все|всех|выведи|покажи|склади|составь).*(игрок|участник|ник|юз|username|юзернейм)|^(ники|юзы)$", re.I)
_PLATFORM_LIST_RE = re.compile(
    r"(бедрок|бэдрок|bedrock|java|джав|жав)\w*.*(игрок|участник|ник)|(игрок|участник|ник)\w*.*(бедрок|бэдрок|bedrock|java|джав|жав)", re.I
)
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


async def _players_report(message: types.Message, request: str = ""):
    flt = parse_player_filter(request)
    result = await bot_list_current_participants()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список участников.")
        return
    rows = apply_player_filter(result.data, flt)
    if not result.data:
        await message.answer("ℹ️ Участников пока нет.")
        return
    if not rows:
        await message.answer(f"ℹ️ Подходящих участников нет ({escape(flt.describe())}).")
        return
    lines = []
    for index, row in enumerate(rows, 1):
        nick = escape(str(row.get("nickname") or "—"))
        if flt.nicks_only:
            lines.append(f"{index}. <code>{nick}</code>")
            continue
        name = escape(str(row.get("display_name") or "—"))
        username = row.get("username")
        user = f"@{escape(str(username))}" if username else "—"
        lines.append(f"{index}. {name} · {user} · <code>{nick}</code>")
    title = "👥 <b>Участники PRISMA" + (f" — {escape(flt.describe())}" if flt.is_filtered else "") + f" ({len(lines)})</b>"
    if not flt.nicks_only:
        title += "\nИмя · Telegram · Minecraft"
    if flt.unsupported:
        title += "\nℹ️ Часть условий без ИИ не применяется, показан список по платформе/юзернейму."
    await _send_long(message, title, lines, "prisma_players.txt")


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
    if _PLAYERS_RE.search(request) or _PLATFORM_LIST_RE.search(request):
        flt = parse_player_filter(request)
        # Conditions the code cannot apply (online, clan, level…) go to the model when it is available.
        if not (flt.unsupported and is_configured("admin")):
            if await _has(admin_id, "player.view"):
                await _players_report(message, request)
            else:
                await message.answer("❌ Недостаточно прав.")
            return

    if not is_configured("admin"):
        await message.answer("🤖 PRISMA_AI не настроен: задайте AI_API_KEY_ADMIN.")
        return
    waiting = await message.answer("🤖 Работаю…")
    try:
        text, cards = await run_copilot(admin_id, request)
    except AIError as exc:
        logger.warning("copilot model failed: %s", exc)
        await waiting.edit_text("😕 Не получилось выполнить запрос. Попробуйте проще, например: «заявки», «игроки бедрок» или «неактив 14». Проверка связи: /ai_status")
        return
    await _send_model_text(waiting, message, text, None)
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
        "🤖 <b>PRISMA_AI</b>\nНапишите задачу, например:\n• список игроков и их юзы\n• кто неактивен месяц\n• какие заявки ждут\n"
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
        await callback.message.answer("🤖 PRISMA_AI: напишите задачу (например «список игроков и их юзы»). /cancel — выйти.")


@router.message(Command("cancel"), StateFilter(AskForm.admin_waiting))
async def copilot_cancel(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("Ок, PRISMA_AI закрыт.")


@router.message(StateFilter(AskForm.admin_waiting), F.text, ~F.text.startswith("/"))
async def copilot_waiting(message: types.Message, state: FSMContext):
    await state.clear()
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    await _copilot(message, message.text)


# ---------------------------------------------------------------- group chats
group_router = Router(name="ai_group")


@group_router.message(Command("ai", "pai", "prisma_ai"), F.chat.type.in_({"group", "supergroup"}))
async def group_ai(message: types.Message, command: CommandObject):
    question = (command.args or "").strip()
    if not question and message.reply_to_message:
        question = (message.reply_to_message.text or "").strip()
    if not question:
        await message.reply("🤖 PRISMA_AI: напишите вопрос после команды, например /ai что такое призма")
        return
    await _answer(message, question, private=False)


@group_router.message(F.chat.type.in_({"group", "supergroup"}), F.text)
async def group_talk(message: types.Message):
    """Talk to PRISMA_AI in a group by mentioning the bot or replying to it.

    Anything else, and anything that looks like spam (links, long text, over the rate limit),
    is passed on untouched so automod still sees it.
    """
    text = message.text or ""
    if text.startswith("/") or not message.from_user or len(text) > 400:
        raise SkipHandler
    me = await message.bot.me()
    mentioned = f"@{(me.username or '').lower()}" in text.lower()
    reply = message.reply_to_message
    replied = bool(reply and reply.from_user and reply.from_user.id == me.id)
    if not (mentioned or replied):
        raise SkipHandler
    if any(entity.type in {"url", "text_link"} for entity in (message.entities or [])):
        raise SkipHandler
    if navigator.is_limited(message.from_user.id):
        raise SkipHandler
    question = re.sub(f"@{re.escape(me.username or '')}", "", text, flags=re.I).strip()
    await _answer(message, question, private=False)


# ------------------------------------------------------------ confirm cards
_CARD_KINDS = {"mk": "market", "sp": "support", "ev": "events"}


@router.callback_query(F.data.startswith("aim:"))
async def member_card(callback: types.CallbackQuery):
    parts = (callback.data or "").split(":")
    if len(parts) != 4 or parts[1] not in _CARD_KINDS or parts[2] not in {"ok", "no", "edit"}:
        await callback.answer("Кнопка устарела.", show_alert=True)
        return
    _, kind, action, draft_id = parts
    tg_id = callback.from_user.id
    if action == "edit":
        draft = peek_draft(draft_id, tg_id)
        if not draft:
            await callback.answer("Черновик устарел — попросите PRISMA_AI подготовить новый.", show_alert=True)
            return
        ai_memory.remember(callback.message.chat.id, tg_id, "assistant", f"Черновик ({kind}): {draft['payload']}")
        await callback.answer("Напишите в чат, что изменить.")
        await callback.message.answer("✏️ Напишите, что поправить (цена, текст, срок) — я подготовлю обновлённую карточку.")
        return
    draft = take_draft(draft_id, tg_id)
    if not draft or draft["kind"] != kind:
        await callback.answer("Черновик устарел или не ваш.", show_alert=True)
        return
    if action == "no":
        await callback.answer("Отменено")
        await _finish_card(callback, "✖ Отменено.")
        return
    if kind in {"mk", "ev"} and await get_application_status(tg_id) != "ACCEPTED":
        await callback.answer("Доступно после одобрения заявки.", show_alert=True)
        return
    ok, text = await publish(kind, draft["payload"], tg_id)
    await callback.answer("Готово" if ok else "Не получилось")
    await _finish_card(callback, text)


async def _finish_card(callback: types.CallbackQuery, text: str) -> None:
    try:
        await callback.message.edit_text(text, reply_markup=None)
    except Exception:
        await callback.message.answer(text)


@router.callback_query(F.data.startswith("aio:"))
async def ops_card(callback: types.CallbackQuery):
    """Confirm cards for top-staff operations. Ownership, admin mode and the top role are re-checked on every tap."""
    parts = (callback.data or "").split(":")
    if len(parts) != 4 or parts[1] not in {"rd", "an"} or parts[2] not in {"ok", "no"}:
        await callback.answer("Кнопка устарела.", show_alert=True)
        return
    _, kind, action, draft_id = parts
    admin_id = callback.from_user.id
    draft = take_draft(draft_id, admin_id)
    if not draft or draft["kind"] != kind:
        await callback.answer("Карточка устарела или не ваша.", show_alert=True)
        return
    if action == "no":
        await callback.answer("Отменено")
        await _finish_card(callback, "✖ Отменено.")
        return
    from utils.permissions import staff_context
    context = await staff_context(admin_id)
    if not (context.get("is_staff") and "*" in context.get("permissions", [])) or not await is_admin_mode(admin_id):
        await callback.answer("❌ Недостаточно прав.", show_alert=True)
        return
    if kind == "rd":
        from services.ai import ops
        ok, detail = await ops.render_redeploy()
        text = f"🚀 Деплой запущен ({detail})." if ok else f"❌ Не удалось перезапустить: {detail}"
    else:
        chat = os.getenv("ANNOUNCE_CHAT_ID", "").strip()
        try:
            await callback.bot.send_message(int(chat), draft["payload"]["text"])
            text, ok = "📣 Объявление отправлено.", True
        except Exception as exc:
            logger.warning("announcement failed: %s", exc)
            text, ok = "❌ Не удалось отправить объявление.", False
    await callback.answer("Готово" if ok else "Не получилось")
    await _finish_card(callback, text)
