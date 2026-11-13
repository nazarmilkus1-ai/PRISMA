from aiogram import F, Router, types

def application_error_message(error: str) -> str:
    messages = {
        "APPLICATION_PENDING": "У вас уже есть заявка на рассмотрении.",
        "APPLICATION_ALREADY_ACTIVE": "У вас уже есть одобренный доступ к PRISMA.",
        "APPLICATION_COOLDOWN": "Повторная подача пока недоступна. Дождитесь окончания cooldown.",
        "AGE_TOO_YOUNG": "Для подачи заявки вы должны соответствовать возрастному ограничению PRISMA.",
        "INVALID_MINECRAFT_NICK": "Некорректный Minecraft-ник.",
        "MINECRAFT_NICK_TAKEN": "Этот Minecraft-ник уже используется.",
        "TELEGRAM_NOT_LINKED": "Telegram-аккаунт ещё не связан с профилем PRISMA.",
        "USER_NOT_FOUND": "Профиль PRISMA не найден. Запустите /start ещё раз.",
    }
    return messages.get(error, "Не удалось отправить заявку. Попробуйте ещё раз.")

from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext
from html import escape
from datetime import datetime
from config import ADMIN_GROUP_ID
from db.rpc import bot_get_pending_count, bot_get_user_status, bot_submit_application, bot_touch_user
from fsm.states import ApplicationForm
from keyboards.inline import agreement_keyboard, platform_keyboard, preview_keyboard, discovery_source_keyboard, APPLICATION_DISCOVERY_SOURCES
from utils.helpers import bedrock_gamertag, bedrock_server_nick, validate_birth_date, validate_minecraft_nick, validate_text

from services.community_membership import clear_onboarding_restriction

router = Router()

@router.message(Command("application"))
async def application_command(message: types.Message, state: FSMContext):
    status = await bot_get_user_status(message.from_user.id)
    if status in ("PENDING", "ACCEPTED"):
        await message.answer("⏳ У вас уже есть активная заявка или доступ к серверу.")
        return
    if status == "ERROR":
        await message.answer("❌ Ошибка соединения с базой данных.")
        return
    await bot_touch_user(
        message.from_user.id,
        message.from_user.username or "",
        message.from_user.first_name or "",
        message.from_user.last_name or "",
        message.from_user.full_name,
        "PRIVATE",
    )
    await state.set_state(ApplicationForm.agreement)
    await message.answer(
        "📝 <b>Подача заявки</b>\n\n"
        "Подавая заявку, вы принимаете правила PRISMA — прочитать их можно командой /rules.\n\n"
        "<b>Разрешаете обработку данных для работы сервера?</b>",
        reply_markup=agreement_keyboard(),
        parse_mode="HTML",
    )

@router.callback_query(F.data == "apply")
async def start_application(callback: types.CallbackQuery, state: FSMContext):
    status = await bot_get_user_status(callback.from_user.id)
    if status in ("PENDING", "ACCEPTED"):
        await callback.answer("У вас уже есть активная заявка.", show_alert=True)
        return
    if status == "ERROR":
        await callback.answer("Ошибка соединения с базой данных.", show_alert=True)
        return
    await callback.answer()
    await bot_touch_user(
        callback.from_user.id,
        callback.from_user.username or "",
        callback.from_user.first_name or "",
        callback.from_user.last_name or "",
        callback.from_user.full_name,
        "PRIVATE",
    )
    await state.set_state(ApplicationForm.agreement)
    await callback.message.edit_text(
        "📝 <b>Подача заявки</b>\n\n"
        "Подавая заявку, вы принимаете правила PRISMA — прочитать их можно командой /rules.\n\n"
        "<b>Разрешаете обработку данных для работы сервера?</b>",
        reply_markup=agreement_keyboard(),
        parse_mode="HTML",
    )

STEPS = 7
SKIP_WORDS = {"пропуск", "пропустить", "-", "—"}


def _step(number: int, text: str) -> str:
    return f"<b>Шаг {number} из {STEPS}:</b> {text}"


def _skip_keyboard():
    return types.InlineKeyboardMarkup(inline_keyboard=[
        [types.InlineKeyboardButton(text="⏭ Пропустить", callback_data="app:skip")],
    ])


def _name_keyboard(tg_name: str):
    label = " ".join(tg_name.split())[:40]
    return types.InlineKeyboardMarkup(inline_keyboard=[
        [types.InlineKeyboardButton(text=f"✅ Это я: {label}", callback_data="app:name_tg")],
    ])


def _edit_keyboard():
    fields = (
        ("name", "👤 Имя"), ("birth", "📅 Дата"), ("nick", "🎮 Ник"),
        ("platform", "🖥 Платформа"), ("about", "📝 О себе"), ("source", "📣 Источник"),
    )
    rows = [
        [types.InlineKeyboardButton(text=fields[i][1], callback_data=f"app:edit:{fields[i][0]}"),
         types.InlineKeyboardButton(text=fields[i + 1][1], callback_data=f"app:edit:{fields[i + 1][0]}")]
        for i in range(0, len(fields), 2)
    ]
    rows.append([types.InlineKeyboardButton(text="↩️ Назад к заявке", callback_data="app:edit:back")])
    return types.InlineKeyboardMarkup(inline_keyboard=rows)


async def _ask_name(message: types.Message, state: FSMContext):
    data = await state.get_data()
    await state.set_state(ApplicationForm.full_name)
    tg_name = str(data.get("tg_full_name") or "").strip()
    await message.answer(
        _step(2, "Как вас зовут? Напишите имя (2–100 символов)."),
        reply_markup=_name_keyboard(tg_name) if 2 <= len(tg_name) <= 100 else None,
        parse_mode="HTML",
    )


async def _ask_birth(message: types.Message, state: FSMContext):
    await state.set_state(ApplicationForm.birth_date)
    await message.answer(_step(3, "Дата рождения в формате ДД.ММ.ГГГГ."), parse_mode="HTML")


async def _ask_nick(message: types.Message, state: FSMContext):
    await state.set_state(ApplicationForm.minecraft_nick)
    await message.answer(
        _step(4, "Ваш Minecraft-ник.\nBedrock: пишите Gamertag как в Xbox, пробелы можно (например, D1lan ok) — "
                 "на сервере он станет .D1lan_ok сам."),
        parse_mode="HTML")


async def _ask_platform(message: types.Message, state: FSMContext):
    await state.set_state(ApplicationForm.platform)
    await message.answer(_step(5, "На чём играете?"), reply_markup=platform_keyboard(), parse_mode="HTML")


async def _ask_about(message: types.Message, state: FSMContext):
    await state.set_state(ApplicationForm.about)
    await message.answer(
        _step(6, "Коротко о себе и о том, что хотите делать на сервере.\n\nНеобязательно."),
        reply_markup=_skip_keyboard(),
        parse_mode="HTML",
    )


async def _ask_source(message: types.Message, state: FSMContext):
    await state.set_state(ApplicationForm.discovery_source)
    await message.answer(
        _step(7, "Откуда вы узнали о PRISMA?"),
        reply_markup=discovery_source_keyboard(),
        parse_mode="HTML",
    )


def _server_nick_line(data: dict) -> str:
    if data.get("platform") == "Bedrock" and data.get("minecraft_nick"):
        gamertag = bedrock_gamertag(data["minecraft_nick"])
        if gamertag:
            return f"<b>Ник на сервере:</b> {escape(bedrock_server_nick(gamertag))}\n"
    return ""


async def _show_preview(message: types.Message, state: FSMContext, *, edit: bool = False):
    data = await state.get_data()
    await state.set_state(ApplicationForm.preview)
    preview = (
        "<b>📋 Проверьте заявку</b>\n\n"
        f"<b>Имя:</b> {escape(data['full_name'])}\n"
        f"<b>Дата:</b> {escape(data['birth_date'])} ({data['age']} лет)\n"
        f"<b>Minecraft:</b> {escape(data['minecraft_nick'])}\n"
        f"{_server_nick_line(data)}"
        f"<b>Платформа:</b> {escape(data['platform'])}\n"
        f"<b>О себе:</b> {escape(data.get('about') or 'Не указано')}\n"
        f"<b>Источник:</b> {escape(data.get('discovery_source') or 'Не указано')}\n\n"
        "Всё верно?"
    )
    if edit:
        try:
            await message.edit_text(preview, reply_markup=preview_keyboard(), parse_mode="HTML")
            return
        except Exception:
            pass
    await message.answer(preview, reply_markup=preview_keyboard(), parse_mode="HTML")


async def _after_field(message: types.Message, state: FSMContext, next_step) -> None:
    """After a field is saved: back to the preview when editing, else the next question."""
    data = await state.get_data()
    if data.get("editing"):
        await state.update_data(editing=False)
        await _show_preview(message, state)
        return
    await next_step(message, state)


@router.callback_query(F.data.in_({"agree_yes", "agree_no"}), StateFilter(ApplicationForm.agreement))
async def process_agreement(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    if callback.data == "agree_no":
        await state.clear()
        await callback.message.edit_text("❌ Вы отказались от обработки данных. Вернуться можно через /start.")
        return
    await state.update_data(
        tg_id=callback.from_user.id,
        username=callback.from_user.username or "",
        tg_full_name=callback.from_user.full_name,
        editing=False,
    )
    await _ask_name(callback.message, state)


@router.message(Command("cancel"), StateFilter(ApplicationForm))
async def cancel_application(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("❌ Подача заявки отменена. /start")


@router.callback_query(F.data == "app:name_tg", StateFilter(ApplicationForm.full_name))
async def name_from_telegram(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    data = await state.get_data()
    name = str(data.get("tg_full_name") or "").strip()
    if not validate_text(name, 2, 100):
        await callback.message.answer("❌ Введите имя вручную (2–100 символов).")
        return
    await state.update_data(full_name=name)
    await callback.message.edit_reply_markup(reply_markup=None)
    await _after_field(callback.message, state, _ask_birth)


@router.message(StateFilter(ApplicationForm.full_name))
async def process_full_name(message: types.Message, state: FSMContext):
    value = (message.text or "").strip()
    if not validate_text(value, 2, 100):
        await message.answer("❌ Имя должно содержать 2–100 символов.")
        return
    await state.update_data(full_name=value)
    await _after_field(message, state, _ask_birth)


@router.message(StateFilter(ApplicationForm.birth_date))
async def process_birth_date(message: types.Message, state: FSMContext):
    value = (message.text or "").strip()
    valid, age, error = validate_birth_date(value)
    if not valid:
        await message.answer(f"❌ {error}")
        return
    await state.update_data(birth_date=value, age=age)
    await _after_field(message, state, _ask_nick)


@router.message(StateFilter(ApplicationForm.minecraft_nick))
async def process_minecraft_nick(message: types.Message, state: FSMContext):
    nick = (message.text or "").strip()
    valid, error = validate_minecraft_nick(nick)
    if not valid:
        await message.answer(f"❌ {error}")
        return
    await state.update_data(minecraft_nick=nick)
    await _after_field(message, state, _ask_platform)


@router.callback_query(F.data.in_({"platform_java", "platform_bedrock"}), StateFilter(ApplicationForm.platform))
async def process_platform(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    platform = "Java" if callback.data == "platform_java" else "Bedrock"
    data = await state.get_data()
    valid, error = validate_minecraft_nick(data.get("minecraft_nick", ""), platform)
    await callback.message.edit_reply_markup(reply_markup=None)
    if not valid:
        # The nick was fine for the other platform (for example a Gamertag with a space on Java): ask again.
        await callback.message.answer(f"❌ {error}")
        await _ask_nick(callback.message, state)
        return
    update = {"platform": platform}
    if platform == "Bedrock":
        gamertag = bedrock_gamertag(data["minecraft_nick"])
        update["minecraft_nick"] = gamertag
    await state.update_data(**update)
    await _after_field(callback.message, state, _ask_about)


@router.callback_query(F.data == "app:skip", StateFilter(ApplicationForm.about))
async def skip_about(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    await state.update_data(about="")
    await callback.message.edit_reply_markup(reply_markup=None)
    await _after_field(callback.message, state, _ask_source)


@router.message(StateFilter(ApplicationForm.about))
async def process_about(message: types.Message, state: FSMContext):
    value = (message.text or "").strip()
    value = "" if value.lower() in SKIP_WORDS else value
    if value and not validate_text(value, 1, 1000):
        await message.answer("❌ Максимум 1000 символов.")
        return
    await state.update_data(about=value)
    await _after_field(message, state, _ask_source)


@router.callback_query(F.data.startswith("discovery:"), StateFilter(ApplicationForm.discovery_source))
async def process_discovery_source(callback: types.CallbackQuery, state: FSMContext):
    try:
        index = int(callback.data.split(":", 1)[1])
        source = APPLICATION_DISCOVERY_SOURCES[index]
    except (ValueError, IndexError):
        await callback.answer("Недопустимый источник.", show_alert=True)
        return
    await callback.answer()
    await state.update_data(discovery_source=source, editing=False)
    await _show_preview(callback.message, state, edit=True)


@router.callback_query(F.data == "cancel", StateFilter(ApplicationForm.preview))
async def cancel_preview(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    await state.clear()
    await callback.message.edit_text("❌ Заявка отменена. /start")


@router.callback_query(F.data == "edit", StateFilter(ApplicationForm.preview))
async def edit_preview(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    await callback.message.edit_text("✏️ Что изменить?", reply_markup=_edit_keyboard())


@router.callback_query(F.data.startswith("app:edit:"), StateFilter(ApplicationForm.preview))
async def edit_field(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    field = callback.data.split(":", 2)[2]
    if field == "back":
        await _show_preview(callback.message, state, edit=True)
        return
    asks = {
        "name": _ask_name, "birth": _ask_birth, "nick": _ask_nick,
        "platform": _ask_platform, "about": _ask_about, "source": _ask_source,
    }
    ask = asks.get(field)
    if not ask:
        return
    await state.update_data(editing=True)
    await callback.message.edit_reply_markup(reply_markup=None)
    await ask(callback.message, state)


@router.callback_query(F.data == "confirm", StateFilter(ApplicationForm.preview))
async def confirm_application(callback: types.CallbackQuery, state: FSMContext):
    await callback.answer()
    data = await state.get_data()
    birth_date = datetime.strptime(data["birth_date"], "%d.%m.%Y").date().isoformat()
    result = await bot_submit_application(
        data["tg_id"],
        data.get("username", ""),
        data["full_name"],
        birth_date,
        data["minecraft_nick"],
        data["platform"],
        data.get("goal") or None,
        data.get("about") or None,
        data.get("discovery_source"),
    )
    if result.error:
        await callback.message.edit_text(
            f"❌ {escape(application_error_message(result.error))}",
            parse_mode="HTML",
        )
        return
    await state.clear()
    await clear_onboarding_restriction(callback.bot, int(data["tg_id"]))
    await callback.message.edit_text(
        "✅ Ваша заявка отправлена администрации. Мы свяжемся с вами после принятия решения."
    )
    count = await bot_get_pending_count()
    if count >= 3 and ADMIN_GROUP_ID:
        try:
            await callback.bot.send_message(
                ADMIN_GROUP_ID,
                f"📋 Внимание! Есть {count} новых заявок, ожидающих рассмотрения.",
            )
        except Exception:
            pass
