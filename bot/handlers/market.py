from datetime import datetime, timedelta, timezone
from html import escape
from uuid import UUID

from aiogram import F, Router, types
from aiogram.filters import Command

from db.rpc import (
    bot_close_market_inquiry,
    bot_close_market_listing,
    bot_create_market_inquiry,
    bot_create_market_offer,
    bot_get_market_offers,
    bot_respond_market_offer,
    bot_withdraw_market_offer,
    bot_create_market_listing,
    bot_get_market,
    bot_get_market_inquiries,
    bot_update_market_listing,
    bot_respond_market_inquiry,
)
from utils.permissions import is_approved

router = Router(name="market")

KIND_LABELS = {
    "SELL": "Продам",
    "BUY": "Куплю",
    "TRADE": "Обмен",
    "SERVICE": "Услуга",
    "OTHER": "Другое",
}
KIND_ALIASES = {
    "продам": "SELL",
    "продать": "SELL",
    "куплю": "BUY",
    "купить": "BUY",
    "обмен": "TRADE",
    "обменяю": "TRADE",
    "услуга": "SERVICE",
    "помогу": "SERVICE",
    "другое": "OTHER",
}
EXPIRY_DAYS = {"0": None, "1": 1, "3": 3, "7": 7, "14": 14, "30": 30}


def _split_pipe(value: str) -> list[str]:
    return [part.strip() for part in value.split("|")]


def _uuid(value: str) -> str | None:
    try:
        return str(UUID(value.strip()))
    except (ValueError, AttributeError):
        return None


def _expiry(days: str) -> str | None:
    if days not in EXPIRY_DAYS:
        return None
    amount = EXPIRY_DAYS[days]
    if amount is None:
        return None
    return (datetime.now(timezone.utc) + timedelta(days=amount)).isoformat()


def _format_listing(row: dict, index: int) -> str:
    kind = KIND_LABELS.get(str(row.get("kind") or "OTHER"), str(row.get("kind") or "Другое"))
    seller = escape(str(row.get("minecraft_nickname") or "Участник"))
    title = escape(str(row.get("title") or "Без названия"))
    description = str(row.get("description") or "").strip()
    price = str(row.get("price_text") or "").strip()
    terms = str(row.get("terms") or "").strip()
    lines = [
        f"<b>{index}. {title}</b>",
        f"{kind} · <code>{seller}</code>",
        f"ID: <code>{escape(str(row.get('id') or ''))}</code>",
    ]
    if description:
        lines.append(escape(description[:500]))
    if price:
        lines.append(f"Цена: <b>{escape(price)}</b>")
    if terms:
        lines.append(f"Условия: {escape(terms[:300])}")
    return "\n".join(lines)


def _format_inquiry(row: dict, index: int) -> str:
    status = {
        "OPEN": "Ожидает ответа",
        "ANSWERED": "Есть ответ",
        "CLOSED": "Закрыт",
    }.get(str(row.get("status") or ""), str(row.get("status") or "—"))
    direction = "Входящий" if row.get("incoming") else "Ваш запрос"
    partner = escape(str(row.get("partner_nickname") or "Участник"))
    title = escape(str(row.get("listing_title") or "Объявление"))
    lines = [
        f"<b>{index}. {title}</b>",
        f"{direction} · {partner} · {status}",
        f"ID: <code>{escape(str(row.get('id') or ''))}</code>",
        f"Сообщение: {escape(str(row.get('message') or '')[:700])}",
    ]
    if row.get("response"):
        lines.append(f"Ответ: {escape(str(row['response'])[:900])}")
    return "\n".join(lines)


OFFER_STATUS = {"PENDING": "⏳ ждёт ответа", "ACCEPTED": "✅ принято", "REJECTED": "❌ отклонено",
                "COUNTERED": "🔁 встречное предложение", "WITHDRAWN": "↩️ отозвано"}


def _format_offer(row: dict, index: int) -> str:
    title = escape(str(row.get("listing_title") or "Объявление"))
    partner = escape(str(row.get("partner_nickname") or "Участник"))
    who = "Вы предложили" if row.get("mine") else f"{partner} предлагает"
    status = "⌛ истекло" if row.get("expired") else OFFER_STATUS.get(str(row.get("status") or ""), "—")
    lines = [f"<b>{index}. {title}</b>", f"{who}: <b>{escape(str(row.get('price_text') or '—'))}</b> · {status} · раунд {row.get('round', 1)}/6"]
    if row.get("note"):
        lines.append(f"Заметка: {escape(str(row['note'])[:300])}")
    lines.append(f"ID: <code>{escape(str(row.get('id') or ''))}</code>")
    return "\n".join(lines)


def _offer_buttons(row: dict) -> types.InlineKeyboardMarkup | None:
    offer_id = str(row.get("id") or "")
    if not _uuid(offer_id):
        return None
    if row.get("actionable"):
        return types.InlineKeyboardMarkup(inline_keyboard=[[
            types.InlineKeyboardButton(text="✅ Принять", callback_data=f"mko:acc:{offer_id}"),
            types.InlineKeyboardButton(text="❌ Отклонить", callback_data=f"mko:rej:{offer_id}"),
        ]])
    if row.get("mine") and row.get("status") == "PENDING" and not row.get("expired"):
        return types.InlineKeyboardMarkup(inline_keyboard=[[
            types.InlineKeyboardButton(text="↩️ Отозвать", callback_data=f"mko:wd:{offer_id}"),
        ]])
    return None


def _error(result, fallback: str = "Не удалось выполнить действие.") -> str:
    raw = str(result.error or "").strip()
    aliases = {
        "PLAYER_ACCESS_REQUIRED": "Рынок доступен только одобренным участникам с whitelist.",
        "USER_NOT_FOUND": "Профиль PRISMA не найден.",
        "INVALID_LISTING": "Проверьте тип, заголовок и длину полей объявления.",
        "LISTING_NOT_FOUND": "Объявление не найдено, снято или уже недоступно.",
        "SELF_LISTING_FORBIDDEN": "Нельзя отправить запрос на собственное объявление.",
        "INQUIRY_ALREADY_OPEN": "По этому объявлению у вас уже есть открытый запрос.",
        "INVALID_INQUIRY": "Сообщение запроса должно содержать от 3 до 1000 символов.",
        "INVALID_INQUIRY_RESPONSE": "Ответ должен содержать от 3 до 1500 символов.",
        "INQUIRY_NOT_FOUND": "Запрос не найден или уже закрыт.",
        "INQUIRY_FORBIDDEN": "У вас нет доступа к этому запросу.",
        "INQUIRY_CLOSED": "Этот запрос уже закрыт.",
        "INQUIRY_ALREADY_ANSWERED": "На этот запрос уже ответили.",
        "INVALID_OFFER": "Цена — от 1 до 60 символов, заметка — до 300.",
        "OFFER_ALREADY_OPEN": "По этому объявлению у вас уже есть активное предложение.",
        "OFFER_NOT_FOUND": "Предложение не найдено или уже закрыто.",
        "OFFER_FORBIDDEN": "Ответить на это предложение может только другая сторона.",
        "OFFER_CLOSED": "Это предложение уже обработано.",
        "OFFER_EXPIRED": "Время на ответ (72 часа) истекло. Предложите цену заново.",
        "OFFER_MAX_ROUNDS": "Достигнут лимит из 6 раундов торга: договоритесь лично.",
        "INVALID_OFFER_ACTION": "Неизвестное действие.",
    }
    return aliases.get(raw, fallback)


async def _show_market(message: types.Message, tg_id: int):
    result = await bot_get_market(tg_id, limit=12)
    if result.error or not isinstance(result.data, list):
        await message.answer(_error(result, "Не удалось загрузить объявления."))
        return
    if not result.data:
        await message.answer("🛒 <b>Рынок PRISMA</b>\n\nПока нет активных объявлений.", parse_mode="HTML")
        return
    blocks = [
        "🛒 <b>Рынок PRISMA</b>",
        "Запрос: <code>/рынок запрос ID | сообщение</code>",
        "Торг: <code>/рынок предложить ID | цена | заметка</code>",
        "",
    ]
    blocks.extend(_format_listing(row, i) for i, row in enumerate(result.data[:12], 1))
    await message.answer("\n\n".join(blocks), parse_mode="HTML")


@router.callback_query(F.data == "market")
async def market_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Рынок доступен после одобрения заявки.", show_alert=True)
        return
    await callback.answer()
    if callback.message:
        await _show_market(callback.message, callback.from_user.id)


@router.message(Command("рынок", "market"))
async def market_command(message: types.Message):
    if message.chat.type != "private":
        await message.answer("🛒 Рынок открыт в личном чате бота.")
        return
    if not await is_approved(message.from_user.id):
        await message.answer("⏳ Рынок доступен после одобрения заявки.")
        return

    raw = (message.text or "").strip()
    parts = raw.split(maxsplit=1)
    args = parts[1].strip() if len(parts) > 1 else ""

    if not args:
        await _show_market(message, message.from_user.id)
        return

    command, _, rest = args.partition(" ")
    command = command.casefold()
    rest = rest.strip()

    if command in {"поиск", "search"}:
        if not 1 <= len(rest) <= 64:
            await message.answer("Использование: <code>/рынок поиск ферма</code>", parse_mode="HTML")
            return
        result = await bot_get_market(message.from_user.id, query=rest, limit=12)
        if result.error or not isinstance(result.data, list):
            await message.answer(_error(result, "Не удалось выполнить поиск."))
            return
        if not result.data:
            await message.answer("Ничего не найдено.")
            return
        blocks = [f"🔎 <b>Результаты: {escape(rest)}</b>", ""]
        blocks.extend(_format_listing(row, i) for i, row in enumerate(result.data[:12], 1))
        await message.answer("\n\n".join(blocks), parse_mode="HTML")
        return

    if command in {"торг", "offers", "bargain"}:
        result = await bot_get_market_offers(message.from_user.id)
        if result.error or not isinstance(result.data, list):
            await message.answer(_error(result, "Не удалось загрузить торг."))
            return
        if not result.data:
            await message.answer(
                "🤝 Торгов пока нет.\nПредложить цену: <code>/рынок предложить ID | цена | заметка</code>",
                parse_mode="HTML",
            )
            return
        await message.answer("🤝 <b>Ваш торг</b>\nВстречная цена: <code>/рынок встречная ID | цена | заметка</code>", parse_mode="HTML")
        for i, row in enumerate(result.data[:10], 1):
            await message.answer(_format_offer(row, i), parse_mode="HTML", reply_markup=_offer_buttons(row))
        return

    if command in {"предложить", "offer"}:
        fields = _split_pipe(rest)
        listing_id = _uuid(fields[0]) if fields else None
        if not listing_id or len(fields) not in {2, 3}:
            await message.answer("Использование: <code>/рынок предложить ID | цена | заметка</code>", parse_mode="HTML")
            return
        result = await bot_create_market_offer(message.from_user.id, listing_id, fields[1], fields[2] if len(fields) == 3 else None)
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("✅ Предложение отправлено. Продавец ответит в течение 72 часов.\nСмотреть: <code>/рынок торг</code>", parse_mode="HTML")
        return

    if command in {"встречная", "counter"}:
        fields = _split_pipe(rest)
        offer_id = _uuid(fields[0]) if fields else None
        if not offer_id or len(fields) not in {2, 3}:
            await message.answer("Использование: <code>/рынок встречная ID | цена | заметка</code>", parse_mode="HTML")
            return
        result = await bot_respond_market_offer(message.from_user.id, offer_id, "counter", fields[1], fields[2] if len(fields) == 3 else None)
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("🔁 Встречное предложение отправлено.")
        return

    if command in {"мои", "мои-запросы", "inbox", "my"}:
        result = await bot_get_market_inquiries(message.from_user.id)
        if result.error or not isinstance(result.data, list):
            await message.answer(_error(result, "Не удалось загрузить ваши запросы."))
            return
        if not result.data:
            await message.answer("📨 У вас пока нет запросов по рынку.")
            return
        blocks = ["📨 <b>Ваши запросы по рынку</b>", ""]
        blocks.extend(_format_inquiry(row, i) for i, row in enumerate(result.data[:20], 1))
        blocks.extend([
            "",
            "Ответ: <code>/рынок ответ ID | текст</code>",
            "Закрыть: <code>/рынок закрыть ID</code>",
        ])
        await message.answer("\n\n".join(blocks), parse_mode="HTML")
        return

    if command in {"создать", "create"}:
        fields = _split_pipe(rest)
        if len(fields) not in {5, 6}:
            await message.answer(
                "Использование:\n"
                "<code>/рынок создать Продам | Заголовок | Описание | Цена | Условия | 14</code>\n"
                "Срок: 0, 1, 3, 7, 14 или 30 дней.",
                parse_mode="HTML",
            )
            return
        kind = KIND_ALIASES.get(fields[0].casefold(), fields[0].upper())
        expiry_days = fields[5] if len(fields) == 6 else "0"
        if kind not in KIND_LABELS or expiry_days not in EXPIRY_DAYS:
            await message.answer("Проверьте тип объявления и срок.")
            return
        result = await bot_create_market_listing(
            message.from_user.id,
            kind,
            fields[1],
            fields[2] or None,
            fields[3] or None,
            fields[4] or None,
            _expiry(expiry_days),
        )
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        listing_id = result.data.get("listing_id") if isinstance(result.data, dict) else None
        await message.answer(
            f"✅ Объявление опубликовано.\nID: <code>{escape(str(listing_id or '—'))}</code>",
            parse_mode="HTML",
        )
        return

    if command in {"редактировать", "edit", "изменить"}:
        fields = _split_pipe(rest)
        if len(fields) != 7:
            await message.answer(
                "Использование:\n"
                "<code>/рынок редактировать ID | Продам | Заголовок | Описание | Цена | Условия | 14</code>\n"
                "Срок: 0, 1, 3, 7, 14 или 30 дней.",
                parse_mode="HTML",
            )
            return
        listing_id = _uuid(fields[0])
        kind = KIND_ALIASES.get(fields[1].casefold(), fields[1].upper())
        expiry_days = fields[6]
        if not listing_id:
            await message.answer("Некорректный ID объявления.")
            return
        if kind not in KIND_LABELS or expiry_days not in EXPIRY_DAYS:
            await message.answer("Проверьте тип объявления и срок.")
            return
        result = await bot_update_market_listing(
            message.from_user.id,
            listing_id,
            kind,
            fields[2],
            fields[3] or None,
            fields[4] or None,
            fields[5] or None,
            _expiry(expiry_days),
        )
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("✅ Объявление обновлено.")
        return

    if command in {"запрос", "inquiry"}:
        fields = _split_pipe(rest)
        if len(fields) != 2:
            await message.answer("Использование: <code>/рынок запрос ID | ваше сообщение</code>", parse_mode="HTML")
            return
        listing_id = _uuid(fields[0])
        if not listing_id:
            await message.answer("Некорректный ID объявления.")
            return
        result = await bot_create_market_inquiry(message.from_user.id, listing_id, fields[1])
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("✅ Запрос отправлен владельцу объявления.")
        return

    if command in {"ответ", "ответить", "reply"}:
        fields = _split_pipe(rest)
        if len(fields) != 2:
            await message.answer("Использование: <code>/рынок ответ ID | текст ответа</code>", parse_mode="HTML")
            return
        inquiry_id = _uuid(fields[0])
        if not inquiry_id:
            await message.answer("Некорректный ID запроса.")
            return
        result = await bot_respond_market_inquiry(message.from_user.id, inquiry_id, fields[1])
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("✅ Ответ отправлен.")
        return

    if command == "закрыть":
        inquiry_id = _uuid(rest)
        if not inquiry_id:
            await message.answer("Использование: <code>/рынок закрыть ID</code>", parse_mode="HTML")
            return
        result = await bot_close_market_inquiry(message.from_user.id, inquiry_id)
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        await message.answer("✅ Запрос закрыт.")
        return

    if command in {"снять", "закрыть-объявление", "close"}:
        listing_id = _uuid(rest)
        if not listing_id:
            await message.answer("Использование: <code>/рынок снять ID</code>", parse_mode="HTML")
            return
        result = await bot_close_market_listing(message.from_user.id, listing_id)
        if result.error:
            await message.answer(f"❌ {_error(result)}")
            return
        closed = result.data.get("inquiries_closed", 0) if isinstance(result.data, dict) else 0
        await message.answer(f"✅ Объявление снято с публикации. Закрыто запросов: {closed}.")
        return

    await message.answer(
        "🛒 Использование:\n"
        "<code>/рынок</code> — активные объявления\n"
        "<code>/рынок поиск текст</code> — поиск\n"
        "<code>/рынок мои</code> — ваши запросы\n"
        "<code>/рынок создать ...</code> — создать объявление\n"
        "<code>/рынок редактировать ID | тип | заголовок | описание | цена | условия | срок</code> — изменить своё объявление\n"
        "<code>/рынок запрос ID | текст</code> — написать владельцу\n"
        "<code>/рынок предложить ID | цена | заметка</code> — торг: предложить цену\n"
        "<code>/рынок торг</code> — ваши предложения, принять/отклонить\n"
        "<code>/рынок встречная ID | цена</code> — встречная цена\n"
        "<code>/рынок ответ ID | текст</code> — ответить\n"
        "<code>/рынок закрыть ID</code> — закрыть запрос\n"
        "<code>/рынок снять ID</code> — снять своё объявление",
        parse_mode="HTML",
    )


@router.callback_query(F.data.startswith("mko:"))
async def offer_callback(callback: types.CallbackQuery):
    """The RPC enforces that only the other party can answer and only the author can withdraw."""
    parts = (callback.data or "").split(":")
    offer_id = _uuid(parts[2]) if len(parts) == 3 else None
    if not offer_id or parts[1] not in {"acc", "rej", "wd"}:
        await callback.answer("Кнопка устарела.", show_alert=True)
        return
    tg_id = callback.from_user.id
    if parts[1] == "wd":
        result = await bot_withdraw_market_offer(tg_id, offer_id)
        done = "↩️ Предложение отозвано."
    else:
        action = "accept" if parts[1] == "acc" else "reject"
        result = await bot_respond_market_offer(tg_id, offer_id, action)
        done = "✅ Вы приняли предложение. Договоритесь о передаче в игре." if action == "accept" else "❌ Предложение отклонено."
    if result.error:
        await callback.answer(_error(result), show_alert=True)
        return
    await callback.answer("Готово")
    try:
        await callback.message.edit_text(done, reply_markup=None)
    except Exception:
        await callback.message.answer(done)
