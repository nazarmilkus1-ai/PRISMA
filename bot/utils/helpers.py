import re
from datetime import date, datetime
from html import escape

MAX_TEXT = 1000


def validate_birth_date(value: str):
    if not re.fullmatch(r"\d{2}\.\d{2}\.\d{4}", value):
        return False, None, "Неверный формат. Используйте ДД.ММ.ГГГГ."
    try:
        birth = datetime.strptime(value, "%d.%m.%Y").date()
    except ValueError:
        return False, None, "Неверная дата."
    today = date.today()
    if birth > today:
        return False, None, "Дата рождения не может быть в будущем."
    age = today.year - birth.year - ((today.month, today.day) < (birth.month, birth.day))
    if age < 14:
        return False, None, "Для подачи анкеты нужно быть не младше 14 лет."
    if age > 120:
        return False, None, "Некорректная дата рождения."
    return True, age, None


_JAVA_NICK = re.compile(r"[A-Za-z0-9_]{3,16}")
_BEDROCK_NICK = re.compile(r"[A-Za-z0-9_ ]{3,15}")


def bedrock_gamertag(raw: str) -> str | None:
    """Canonical Bedrock Gamertag, or None. Mirrors private.prisma_bedrock_gamertag in the database.

    Players type what they see in Xbox: "D1lan ok", sometimes with a leading "." (the server form) or a
    modern "#1234" suffix. 15 characters is Floodgate's 16-character username limit minus the "." prefix.
    """
    value = (raw or "").strip()
    value = re.sub(r"^\.", "", value)
    value = re.sub(r"#[0-9]{1,6}$", "", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value if _BEDROCK_NICK.fullmatch(value) else None


def bedrock_server_nick(gamertag: str) -> str:
    """The name the server sees for that Gamertag (Floodgate: "." prefix, spaces become "_")."""
    return "." + gamertag.replace(" ", "_")


def validate_minecraft_nick(nick: str, platform: str | None = None):
    """platform: "java" / "bedrock" (any case) or None while it is not chosen yet — then either form is fine."""
    nick = (nick or "").strip()
    if not nick:
        return False, "Ник не может быть пустым."
    kind = (platform or "").strip().lower()
    java_ok = bool(_JAVA_NICK.fullmatch(nick))
    bedrock_ok = bedrock_gamertag(nick) is not None
    if kind == "java":
        if java_ok:
            return True, None
        return False, "Java-ник: 3–16 символов, только латиница, цифры и «_», без пробелов."
    if kind == "bedrock":
        if bedrock_ok:
            return True, None
        return False, "Bedrock Gamertag: 3–15 символов, латиница, цифры и пробелы (можно с «_»)."
    if java_ok or bedrock_ok:
        return True, None
    if len(nick) < 3:
        return False, "Ник слишком короткий: минимум 3 символа."
    return False, ("Ник не подходит. Java: 3–16 символов, латиница/цифры/«_». "
                   "Bedrock: Gamertag до 15 символов, пробелы разрешены (например, D1lan ok).")


def validate_text(value: str, min_length=1, max_length=MAX_TEXT):
    if not isinstance(value, str):
        return False
    value = value.strip()
    return min_length <= len(value) <= max_length


def format_punishment(p: dict) -> str:
    status = str(p.get("status", "unknown"))
    icon = "🟠" if status == "active" else "⚪"
    expires_at = p.get("expires_at")
    expires = f"до {expires_at}" if expires_at else "бессрочно"
    return (
        f"{icon} <b>{escape(str(p.get('type', 'unknown')).upper())}</b>\n"
        f"Причина: {escape(str(p.get('reason', 'Не указано')))}\n"
        f"Статус: {escape(status)} ({escape(expires)})\n"
        f"Выдано: {escape(str(p.get('issued_at', 'неизвестно')))}"
    )


def parse_duration(value: str) -> int:
    value = " ".join(value.strip().lower().split())
    match = re.fullmatch(
        r"(\d+)\s*(s|m|h|d|w|сек|секунд(?:а|ы)?|мин|минут(?:а|ы)?|ч|час(?:а|ов)?|д|дн(?:я|ей)?|день|н|нед(?:еля|ели|ель)?)",
        value,
    )
    if not match:
        raise ValueError("Неверный формат. Пример: 10m, 10 минут, 2h, 2 часа, 7d или 1 неделя.")
    amount = int(match.group(1))
    unit = match.group(2)
    seconds = amount * {
        "s": 1, "сек": 1, "секунд": 1, "секунда": 1, "секунды": 1,
        "m": 60, "мин": 60, "минута": 60, "минут": 60,
        "h": 3600, "ч": 3600, "час": 3600, "часа": 3600, "часов": 3600,
        "d": 86400, "д": 86400, "дн": 86400, "дня": 86400, "дней": 86400, "день": 86400,
        "w": 604800, "н": 604800, "нед": 604800, "неделя": 604800, "недели": 604800, "недель": 604800,
    }[unit]
    if seconds <= 0:
        raise ValueError("Длительность должна быть больше 0.")
    if seconds > 30 * 86400:
        raise ValueError("Максимальная длительность — 30 дней.")
    return seconds


def parse_command_args(text: str) -> list[str]:
    # shlex даёт корректную поддержку причин в кавычках для /ban nick "reason"
    import shlex
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()
