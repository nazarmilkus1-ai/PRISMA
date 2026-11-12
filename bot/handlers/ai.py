import asyncio
import logging
import os
import re
import time
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.dispatcher.event.bases import SkipHandler
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

import config
from db.rpc import bot_get_profile, bot_get_user_status
from fsm.states import AskForm
from handlers.guide import build_guide
from db.rpc import bot_check_admin_permission
from services.ai import ambient, evals
from services.ai import memory as ai_memory
from services.ai import navigator, sections
from services.ai.admin_tools import run_copilot
from services.ai.bench import run_bench
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.links import link_buttons
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from services.ai.live import live_answer, live_intent
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
    """PRISMA_AI thinks for itself: with a model configured every question goes to it (with tools).
    The deterministic answers below are only the fallback when the model is not configured or fails."""
    question = (question or "").strip() or "Привет"
    if is_configured("user"):
        if await _ask_ai(message, question, private):
            return
    await _answer_by_code(message, question, private)


async def _answer_by_code(message: types.Message, question: str, private: bool):
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

    matched = sections.match_sections(question)
    if matched:
        status = str(await bot_get_user_status(tg_id) or "")
        built = sections.build_answer(question, status)
        if built:
            await message.answer(built[0], reply_markup=built[1])
            return
    if not private:
        # Never open the member menu in a group chat: it belongs in the private chat only.
        me = await message.bot.me()
        markup = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(
            text="🤖 Написать PRISMA_AI в личке", url=ambient.invite_url(me.username or "", "general"))]])
        await message.reply("😕 Сейчас не получилось ответить. Попробуй ещё раз или напиши мне в личку.",
                            reply_markup=markup, allow_sending_without_reply=True)
        return
    if is_configured("user"):
        await _fallback_menu(message, "😕 Не получилось ответить. Выберите нужный раздел:")
    else:
        await _fallback_menu(message, "🤖 PRISMA_AI пока не подключён, но вот куда можно нажать:")


async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Returns True when the model answered; False sends the caller to the code fallback."""
    tg_id = message.from_user.id
    if not navigator.allowed(tg_id):
        await message.answer("⏳ Слишком много вопросов подряд. Попробуйте чуть позже.")
        return True
    status = str(await bot_get_user_status(tg_id) or "")
    chat_id = message.chat.id
    # Private chat shows a «thinking» message; a group only gets the «typing…» indicator (no clutter, one message less).
    waiting = await message.answer("🤖 PRISMA_AI думает…") if private else None
    if not private:
        try:
            await message.bot.send_chat_action(chat_id, "typing")
        except Exception:
            pass
    try:
        await ai_memory.hydrate(chat_id, tg_id)
        history = ai_memory.history(chat_id, tg_id)
        if private:
            text, cards = await run_member(tg_id, question, status, history, True)
        else:
            text, cards = await run_member(
                tg_id, question, status, history, False,
                chat_context=ambient.transcript(chat_id, 14, exclude_id=message.message_id),
                asker=message.from_user.first_name or "участник", adult=ambient.adult(chat_id))
    except Exception as exc:  # AIError or anything unexpected: never leave «думает…» hanging
        logger.warning("member PRISMA_AI failed: %s", exc)
        if waiting:
            try:
                await waiting.delete()
            except Exception:
                pass
        return False
    answer_id = ai_memory.new_answer_id()
    ai_memory.remember(chat_id, tg_id, "user", question)
    ai_memory.remember(chat_id, tg_id, "assistant", text, answer_id=answer_id)
    asyncio.create_task(ai_memory.persist(chat_id, tg_id, "user", question))
    asyncio.create_task(ai_memory.persist(chat_id, tg_id, "assistant", text, answer_id))
    built = sections.build_answer(question, status) if private and sections.match_sections(question) else None
    rows = list(built[1].inline_keyboard) if built else []
    link_row = link_buttons(question, text)
    rows += [link_row[i:i + 2] for i in range(0, len(link_row), 2)]
    sent = await _send_model_text(waiting, message, text, InlineKeyboardMarkup(inline_keyboard=rows) if rows else None)
    ai_memory.bind(chat_id, sent.message_id, tg_id, answer_id)
    if not private:
        ambient.observe_bot(chat_id, sent.message_id, text, to_user=tg_id)
    for card_text, card_markup in cards:
        await message.answer(card_text, parse_mode="HTML", reply_markup=card_markup)
    return True  # the caller must not add the code fallback after a real answer


_LIKE = {"👍", "❤", "🔥", "👏", "🥰", "💯", "🎉", "🤩", "🙏", "👌", "😍", "❤\u200d🔥"}
_DISLIKE = {"👎", "💩", "🤮", "🤡", "😡", "🤬", "😢"}


@router.message_reaction()
async def on_reaction(event: types.MessageReactionUpdated):
    """A like is a Telegram reaction on the bot's message: remember it so the bot knows how it was received."""
    bound = ai_memory.owner_of(event.chat.id, event.message_id)
    if not bound:
        return
    emojis = {getattr(r, "emoji", None) for r in (event.new_reaction or [])}
    rating = 1 if emojis & _LIKE else -1 if emojis & _DISLIKE else 0
    if rating:
        await ai_memory.rate(bound[0], event.chat.id, bound[1], rating)


async def _send_model_text(waiting, message, text, markup):
    """Model text is converted to escaped Telegram HTML; plain text is the fallback.
    Without a «thinking» message (groups) the answer is sent as a reply to the asker."""
    if waiting is None:
        try:
            return await message.reply(to_telegram_html(text), parse_mode="HTML", reply_markup=markup,
                                       allow_sending_without_reply=True)
        except Exception:
            return await message.reply(strip_markdown(text), reply_markup=markup, allow_sending_without_reply=True)
    try:
        return await waiting.edit_text(to_telegram_html(text), parse_mode="HTML", reply_markup=markup)
    except Exception:
        pass
    plain = strip_markdown(text)
    try:
        return await waiting.edit_text(plain, reply_markup=markup)
    except Exception:
        return await message.answer(plain, reply_markup=markup)


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
    # Staff in admin mode talk to the PRISMA_AGENT, everyone else to the navigator.
    if await is_admin_mode(message.from_user.id):
        await _copilot(message, text)
        return
    await _answer(message, text)


@router.message(Command("ai_eval"), F.chat.type == "private")
async def ai_eval(message: types.Message):
    """Admins: run the golden questions through the real PRISMA_AI and report the pass rate."""
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    if not is_configured("user"):
        await message.answer("Ключ AI_API_KEY_USER не задан.")
        return
    waiting = await message.answer("🧪 Проверяю PRISMA_AI на эталонных вопросах…")
    tg_id = message.from_user.id

    async def ask(question: str) -> str:
        text, _cards = await run_member(tg_id, question, "ACCEPTED", [], True)
        return text

    hosts = (re.sub(r"^https?://", "", config.SITE_URL).split("/")[0].lower(),)
    passed, failures = await evals.run_live(ask, hosts)
    problems = evals.deterministic_failures()
    total = passed + len(failures)
    lines = [f"🧪 <b>Оценка PRISMA_AI</b>: {passed}/{total} ответов прошли проверку"]
    lines += [escape(f) for f in failures[:8]]
    lines.append("Маршрутизация: " + ("✅ всё как задумано" if not problems else "❌ " + escape("; ".join(problems[:3]))))
    await waiting.edit_text("\n".join(lines), parse_mode="HTML")


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


# ---------------------------------------------------------------- admin PRISMA_AGENT


async def _copilot(message: types.Message, request: str):
    request = (request or "").strip()
    if len(request) < 2:
        await message.answer("Напишите, что нужно, например: «список игроков и их юзы».")
        return
    admin_id = message.from_user.id

    if not is_configured("admin"):
        await message.answer("🤖 PRISMA_AGENT не настроен: задайте AI_API_KEY_ADMIN.")
        return
    waiting = await message.answer("🤖 Работаю…")
    try:
        text, cards = await run_copilot(admin_id, request, bot=message.bot)
    except Exception as exc:  # the model, a tool or the gateway failed: say so honestly
        logger.warning("copilot failed: %s", exc)
        await waiting.edit_text("😕 Не получилось выполнить запрос (модель или данные недоступны). Попробуйте ещё раз или переформулируйте. Проверка связи: /ai_status")
        return
    answer_id = ai_memory.new_answer_id()
    asyncio.create_task(ai_memory.persist(message.chat.id, admin_id, "assistant", text, answer_id, agent=True))
    sent = await _send_model_text(waiting, message, text, None)
    ai_memory.bind(message.chat.id, sent.message_id, admin_id, answer_id)
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
        "🤖 <b>PRISMA_AGENT</b>\nНапишите задачу, например:\n• список игроков и их юзы\n• кто неактивен месяц\n• какие заявки ждут\n"
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
        await callback.message.answer("🤖 PRISMA_AGENT: напишите задачу (например «список игроков и их юзы»). /cancel — выйти.")


@router.message(Command("cancel"), StateFilter(AskForm.admin_waiting))
async def copilot_cancel(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("Ок, PRISMA_AGENT закрыт.")


@router.message(StateFilter(AskForm.admin_waiting), F.text, ~F.text.startswith("/"))
async def copilot_waiting(message: types.Message, state: FSMContext):
    await state.clear()
    if not await has_any_staff_permission(message.from_user.id) or not await require_admin_mode(message):
        return
    await _copilot(message, message.text)


# ---------------------------------------------------------------- group chats
group_router = Router(name="ai_group")


@group_router.message(F.chat.type.in_({"group", "supergroup"}), F.text)
async def group_observe(message: types.Message):
    """Remember the last chat lines (RAM only) and, when it looks useful, consider speaking up.
    Always passes the message on, so automod and the mention handler still see everything."""
    user = message.from_user
    text = message.text or ""
    if not user or user.is_bot or message.via_bot or text.startswith("/"):
        raise SkipHandler
    ambient.observe(message.chat.id, message.message_id, user.id, user.first_name or "игрок", text,
                    message.reply_to_message.message_id if message.reply_to_message else None)
    if not ambient.enabled(message.chat.id) or not ambient.worth_considering(text):
        raise SkipHandler
    task = asyncio.create_task(_ambient_reply(message))
    _ambient_tasks.add(task)
    task.add_done_callback(_ambient_tasks.discard)
    raise SkipHandler



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
    named = bool(ambient.addressed_by_name(text))
    # The person is mid-conversation with the bot (it answered them seconds ago): no name needed.
    # Their own line is already in the buffer, so look at the state before it.
    continued = ambient.in_conversation(message.chat.id, message.from_user.id) if not (mentioned or replied or named) else False
    if not (mentioned or replied or named or continued):
        raise SkipHandler
    if any(entity.type in {"url", "text_link"} for entity in (message.entities or [])):
        raise SkipHandler
    if navigator.is_limited(message.from_user.id):
        raise SkipHandler
    question = re.sub(f"@{re.escape(me.username or '')}", "", text, flags=re.I).strip()
    if named:
        question = ambient.strip_name(question)
    await _answer(message, question or "Привет", private=False)


# ------------------------------------------------------------ ambient (unprompted) group talk
_ambient_tasks: set = set()


async def _ambient_reply(message: types.Message):
    try:
        await _ambient_reply_inner(message)
    except Exception as exc:  # never let a background reply crash the bot
        logger.warning("ambient reply failed: %s", exc)


async def _ambient_reply_inner(message: types.Message):
    chat_id, user = message.chat.id, message.from_user
    me = await message.bot.me()
    reply = message.reply_to_message
    if reply and reply.from_user and reply.from_user.id == me.id:
        return  # this is a direct reply to the bot: group_talk handles it
    if f"@{(me.username or '').lower()}" in (message.text or "").lower():
        return
    if not ambient.can_speak(chat_id, user.id) or navigator.is_limited(user.id) or not ambient.classify_budget(chat_id):
        return
    addressed_to_other = bool(reply and reply.from_user and reply.from_user.id != user.id) or any(
        e.type in {"mention", "text_mention"} for e in (message.entities or []))
    if addressed_to_other:
        await asyncio.sleep(ambient.OTHERS_WAIT)  # let a human answer first
        if ambient.answered_by_human(chat_id, message.message_id, user.id):
            return
    decision = await ambient.decide(chat_id, user.first_name or "игрок", message.text or "")
    action = decision.get("action")
    if action == "none" or not ambient.can_speak(chat_id, user.id):
        return
    if action == "invite":
        markup = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(
            text="🤖 Открыть PRISMA_AI в личке", url=ambient.invite_url(me.username or "", decision.get("intent", "general")))]])
        await message.reply(ambient.invite_text(user.first_name or "Друг", decision.get("intent", "general")),
                            parse_mode="HTML", reply_markup=markup, allow_sending_without_reply=True)
        ambient.mark_spoke(chat_id, user.id)
        return
    status = str(await bot_get_user_status(user.id) or "")
    await ai_memory.hydrate(chat_id, user.id)
    text, _cards = await run_member(
        user.id, (message.text or "")[:500], status, ai_memory.history(chat_id, user.id)[-4:], False,
        chat_context=ambient.transcript(chat_id, 14, exclude_id=message.message_id),
        asker=user.first_name or "участник", adult=ambient.adult(chat_id))
    answer_id = ai_memory.new_answer_id()
    ai_memory.remember(chat_id, user.id, "user", message.text or "")
    ai_memory.remember(chat_id, user.id, "assistant", text, answer_id=answer_id)
    asyncio.create_task(ai_memory.persist(chat_id, user.id, "user", message.text or ""))
    asyncio.create_task(ai_memory.persist(chat_id, user.id, "assistant", text, answer_id))
    link_row = link_buttons(message.text or "", text)
    rows = [link_row[i:i + 2] for i in range(0, len(link_row), 2)]
    markup = InlineKeyboardMarkup(inline_keyboard=rows) if rows else None
    try:
        sent = await message.reply(to_telegram_html(text), parse_mode="HTML", reply_markup=markup,
                                   allow_sending_without_reply=True)
    except Exception:
        sent = await message.reply(strip_markdown(text), reply_markup=markup, allow_sending_without_reply=True)
    ai_memory.bind(chat_id, sent.message_id, user.id, answer_id)
    ambient.observe_bot(chat_id, sent.message_id, text, to_user=user.id)
    ambient.mark_spoke(chat_id, user.id)


@group_router.message(Command("ai_chat"), F.chat.type.in_({"group", "supergroup"}))
async def ai_chat_toggle(message: types.Message, command: CommandObject):
    """Chat admins switch the unprompted talk on/off for this chat (until the bot restarts)."""
    member = await message.bot.get_chat_member(message.chat.id, message.from_user.id)
    if member.status not in {"creator", "administrator"}:
        await message.reply("Только администраторы чата могут менять это.")
        return
    arg = (command.args or "").strip().lower()
    if arg in {"on", "вкл", "1"}:
        ambient.set_enabled(message.chat.id, True)
    elif arg in {"off", "выкл", "0"}:
        ambient.set_enabled(message.chat.id, False)
    state = "включено" if ambient.enabled(message.chat.id) else "выключено"
    await message.reply(f"🤖 PRISMA_AI сам отвечает в этом чате: {state}. Команда: /ai_chat on | off")


async def _set_adult_mode(message: types.Message, command: CommandObject, plus: bool):
    member = await message.bot.get_chat_member(message.chat.id, message.from_user.id)
    if member.status not in {"creator", "administrator"}:
        await message.reply("Только администраторы чата могут менять это.")
        return
    arg = (command.args or "").strip().lower()
    if arg.startswith("+"):  # «/ai_18 + on»
        plus, arg = True, arg[1:].strip()
    if arg in {"on", "вкл", "1"}:
        ambient.set_adult(message.chat.id, 2 if plus else 1)
    elif arg in {"off", "выкл", "0"}:
        ambient.set_adult(message.chat.id, 0)
    level = ambient.adult(message.chat.id)
    if level >= 2:
        await message.reply("🔞🔞 Режим 18++: PRISMA_AI без цензуры и без вежливости — жёсткий мат, прожарка, чёрный и пошлый юмор. "
                            "Выключить: /ai_18 off")
    elif level == 1:
        await message.reply("🔞 Режим 18+: мат, чёрный юмор, сленг, подколы. Ещё жёстче: /ai_18+ on. Выключить: /ai_18 off")
    else:
        await message.reply("Режим 18 выключен. Включить: /ai_18 on или /ai_18+ on (только админы чата). "
                            "Чтобы не сбрасывался после перезапуска, добавьте id чата в AI_ADULT_CHATS.")


@group_router.message(Command("ai_18"), F.chat.type.in_({"group", "supergroup"}))
async def ai_adult_toggle(message: types.Message, command: CommandObject):
    await _set_adult_mode(message, command, False)


@group_router.message(Command("ai_18+", "ai_18plus", "ai_18p"), F.chat.type.in_({"group", "supergroup"}))
async def ai_adult_plus_toggle(message: types.Message, command: CommandObject):
    await _set_adult_mode(message, command, True)


# ------------------------------------------------------------ confirm cards
_CARD_KINDS = {"mk": "market", "sp": "support", "ev": "events", "of": "market"}


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
    if kind in {"mk", "ev", "of"} and await get_application_status(tg_id) != "ACCEPTED":
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
