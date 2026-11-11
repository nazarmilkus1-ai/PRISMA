"""Link buttons so nobody has to look for pages by hand. Only fixed site paths, never model-made URLs."""
from __future__ import annotations

import re

from aiogram.types import InlineKeyboardButton

import config

# (pattern, label, path)
_PAGES: tuple[tuple[re.Pattern, str, str], ...] = tuple(
    (re.compile(p, re.I), label, path) for p, label, path in (
        (r"правил|rules", "📜 Правила", "/rules"),
        (r"wiki|вики|википед|гайд|справк", "📚 Wiki", "/wiki"),
        (r"заявк|вступ|анкет|apply", "📝 Подать заявку", "/apply"),
        (r"вход|логин|войти|авторизац|login", "🔑 Вход на сайт", "/login"),
        (r"рынок|маркет|объявлен|продат|купить|торг", "🛒 Рынок", "/market"),
        (r"карт[аыуе]|координат|город|территор", "🗺 Карта", "/map"),
        (r"клан", "⚔️ Кланы", "/clans"),
        (r"ивент|событи|турнир|календар", "🎯 Ивенты", "/events"),
        (r"рейтинг|топ\b|лидер", "🏅 Рейтинг", "/rankings"),
        (r"игрок|участник", "👥 Игроки", "/players"),
        (r"команд", "⌨️ Команды", "/commands"),
        (r"сервер|онлайн|адрес|айпи|\bip\b", "🖥 Сервер", "/server"),
        (r"новост|обновлен|changelog", "📰 Новости", "/news"),
        (r"faq|частые вопрос|вопрос", "❓ FAQ", "/faq"),
        (r"поддержк|помощь|жалоб|апелляц", "🆘 Поддержка", "/faq"),
    )
)


def link_buttons(*texts: str, limit: int = 3) -> list[InlineKeyboardButton]:
    haystack = " ".join(t for t in texts if t)
    base = config.SITE_URL.rstrip("/")
    buttons: list[InlineKeyboardButton] = []
    seen: set[str] = set()
    for pattern, label, path in _PAGES:
        if path in seen or not pattern.search(haystack):
            continue
        seen.add(path)
        buttons.append(InlineKeyboardButton(text=label, url=f"{base}{path}"))
        if len(buttons) >= limit:
            break
    return buttons


def catalog() -> list[dict]:
    base = config.SITE_URL.rstrip("/")
    return [{"title": label, "url": f"{base}{path}"} for _, label, path in _PAGES]
