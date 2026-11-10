"""What the navigator knows: only public product facts, never database rows."""
import re

import config
from handlers.help import SECTIONS
from utils.rules import RULES

_TAG = re.compile(r"<[^>]+>")

ABOUT = (
    "PRISMA — сообщество Minecraft-сервера с whitelist. Через Telegram-бота подают заявку, "
    "получают решение и пользуются сообществом: профиль, топ, кланы, ивенты, рынок, голосования, жалобы. "
    "Сайт: /wiki (Wiki), /rules (правила), /apply (заявка), вход через Telegram. "
    "Доступ на сервер даётся после одобрения заявки; ник Minecraft указывается в заявке или командой /link."
)

MENU = (
    "Главное меню бота (/start): Профиль, Сервер, Топ, Ивенты, Кланы, Рынок, Новости, Голосования, "
    "Жалоба, Поддержка, Уведомления, Ещё (статистика, достижения, Player Battle, команды Minecraft, Java Auth). "
    "/guide — пошаговый чек-лист «что дальше»."
)


def _server_facts() -> str:
    """Addresses only when they are really configured; never invent them."""
    parts = ["Bedrock-игроки заходят через Floodgate: их Minecraft-ник начинается с точки (например .Nick)."]
    java = (config.MINECRAFT_JAVA_ADDRESS or "").strip()
    bedrock = (config.MINECRAFT_BEDROCK_ADDRESS or "").strip()
    if java:
        parts.append(f"Адрес Java: {java}")
    if bedrock:
        parts.append(f"Адрес Bedrock: {bedrock} (порт {config.MINECRAFT_BEDROCK_PORT})")
    parts.append("Онлайн, версия и адреса всегда актуальны в боте: Сервер (кнопка в меню).")
    return " ".join(parts)


def _plain(text: str) -> str:
    return _TAG.sub("", text)


def build_knowledge() -> str:
    parts = [ABOUT, MENU, _server_facts(), "Правила:"]
    parts += [f"{i}. {title}: {body}" for i, (title, body) in enumerate(RULES, 1)]
    parts.append("Команды по разделам:")
    for key, (title, body) in SECTIONS.items():
        if key == "admin":
            continue  # staff commands are not shown to normal users
        parts.append(f"{_plain(title)}\n{_plain(body)}")
    return "\n".join(parts)
