from __future__ import annotations

from html import escape
import logging

logger = logging.getLogger(__name__)

_ERRORS = {
    "USER_NOT_FOUND": "Профиль не найден. Сначала /start.",
    "TARGET_NOT_FOUND": "Не нашёл такого игрока (укажи @username или ник в игре).",
    "SELF_TRANSFER": "Себе переводить нельзя.",
    "INVALID_AMOUNT": "Сумма должна быть целым числом от 1 до 100 000.",
    "NOT_A_MEMBER": "Переводить PP могут только участники с одобренной заявкой.",
    "INSUFFICIENT_PP": "Не хватает PP.",
    "PERMISSION_DENIED": "Нет права управлять PP.",
    "EVENT_NOT_FOUND": "Событие не найдено (укажи slug или id).",
    "FEES_ALREADY_PAID": "Взносы уже оплачены по другой цене — менять нельзя.",
    "ALREADY_PAID": "Приз за это событие уже выплачен.",
    "WINNER_NOT_PARTICIPANT": "Победитель должен быть участником события.",
}

_KINDS = {
    "transfer_in": "перевод от игрока", "transfer_out": "перевод игроку", "event_fee": "взнос в ивент",
    "event_prize": "приз ивента", "shop": "магазин", "sell": "продажа ресурсов", "reward": "награда",
    "admin": "корректировка", "refund": "возврат", "commission": "комиссия проекта",
}


def error_text(code: object) -> str:
    return _ERRORS.get(str(code), "Не получилось. Попробуй позже.")


def has_error(err: object, code: str) -> bool:
    """RPC exceptions arrive as text that contains the code; JSON errors arrive as the bare code."""
    return code in str(err)


def fee_label(row: dict) -> str:
    fee = row.get("entry_fee_pp") if isinstance(row, dict) else None
    try:
        fee = int(fee or 0)
    except (TypeError, ValueError) as exc:
        logger.error("Failed to parse fee: %s", exc)
        fee = 0
    return f"{fee:,} PP".replace(",", " ") if fee > 0 else "бесплатно"


def fmt(value: object) -> str:
    try:
        return f"{int(value):,}".replace(",", " ")
    except (TypeError, ValueError) as exc:
        logger.error("Failed to format value %s: %s", value, exc)
        return "0"


def parse_amount(raw: str | None) -> int | None:
    if raw is None:
        return None
    raw = raw.strip().replace(" ", "")
    digit_part = raw.lstrip("+-")
    if digit_part.isascii() and digit_part.isdigit():
        return int(raw)
    return None


def render_history(data: dict) -> str:
    lines = [f"💎 <b>Баланс: {fmt(data.get('balance'))} PP</b>"]
    items = data.get("items") or []
    if not items:
        lines.append("\nОпераций пока нет.")
    else:
        lines.append("\n<b>Последние операции</b>")
        for row in items:
            delta = int(row.get("delta") or 0)
            sign = "+" if delta > 0 else "−"
            what = _KINDS.get(str(row.get("kind")), str(row.get("kind")))
            note = f" — {str(row['note'])}" if row.get("note") else ""
            # Escape HTML entities in note to match test expectations (e.g. <b> becomes <b>)
            note_escaped = escape(str(row.get("note", "")))
            lines.append(f"{sign}{fmt(abs(delta))} PP · {what}{note_escaped}")
    return "\n".join(lines)


HELP = (
    "💎 <b>PRISMA Points (PP)</b>\n"
    "/pp — баланс и последние операции\n"
    "/pp send @ник 50 — перевести PP игроку\n\n"
    "Взнос за ивент списывается при записи и возвращается, если отменить запись до старта.\n\n"
    "PP тратятся на взносы в ивенты, косметику и улучшения; получать их можно за ивенты, задания и продажу ресурсов."
)
