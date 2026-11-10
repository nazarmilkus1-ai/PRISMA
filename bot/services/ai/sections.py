"""Code-first navigation: map a question to the bot section that answers it.

No model and no database: each intent returns a short hint plus the buttons that
open the real section. Members and guests get different buttons because several
sections only exist after the application is accepted.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup


@dataclass(frozen=True)
class Section:
    key: str
    pattern: re.Pattern
    hint: str
    label: str
    member_cb: str | None
    guest_cb: str | None = None


def _s(key: str, pattern: str, hint: str, label: str, member_cb: str | None, guest_cb: str | None = None) -> Section:
    return Section(key, re.compile(pattern, re.I), hint, label, member_cb, guest_cb)


SECTIONS: tuple[Section, ...] = (
    _s("about", r"что такое (призм|prisma)|что за (проект|сервер|сообществ)|о призм|о prisma|расскажи о (призм|prisma)",
       "PRISMA — сообщество Minecraft-сервера с whitelist: заявка → решение администрации → доступ на сервер. "
       "В боте — профиль, топ, кланы, ивенты, рынок и голосования. Подробнее в разделе «О PRISMA».",
       "📖 О PRISMA", "about_prisma", "about_prisma"),
    _s("server", r"онлайн|айпи|\bip\b|адрес|подключ|\bпорт|статус сервер|сервер (работ|жив|лежит|включ)|кто играет",
       "Статус сервера, онлайн и адреса Java/Bedrock — в разделе «Сервер».", "🖥 Сервер", "player:server", "about_server"),
    _s("stats", r"статистик|сколько (я )?(играл|наиграл)|мой (рейтинг|уровень|xp|опыт)|моя активност",
       "Ваша статистика — в разделе «Ещё → Статистика».", "📊 Статистика", "player:stats"),
    _s("achievements", r"достижен|ачивк|награды", "Достижения — в разделе «Ещё → Достижения».", "🏆 Достижения", "player:achievements"),
    _s("top", r"\bтоп\b|рейтинг|лидер|лучш(ие|их) игрок", "Таблица лидеров — раздел «Топ».", "🏅 Топ", "player:top"),
    _s("events", r"ивент|событи|турнир|мероприят", "Ближайшие ивенты и регистрация — раздел «Ивенты».", "🎯 Ивенты", "player:events"),
    _s("clans", r"клан", "Создание клана, вступление и приглашения — раздел «Кланы».", "⚔️ Кланы", "clans"),
    _s("market", r"рынок|маркет|продат|купить|обмен|объявлен", "Объявления игроков — раздел «Рынок».", "🛒 Рынок", "market"),
    _s("news", r"новост", "Последние новости сообщества.", "📰 Новости", "news", "news"),
    _s("polls", r"голосован|опрос", "Активные голосования — раздел «Голосования».", "🗳 Голосования", "polls"),
    _s("reports", r"жалоб|репорт|читер|нарушител|пожаловат", "Пожаловаться на игрока можно в разделе «Жалоба» или командой /report.", "📢 Жалоба", "reports"),
    _s("support", r"поддержк|связаться|написать админ|апелляц|разбан",
       "Вопрос администрации — раздел «Поддержка» (/support). Апелляция по наказанию — /appeal.", "🆘 Поддержка", "support"),
    _s("link", r"(сменить|изменить|привязать|указать|поменять).*(ник|minecraft|майнкрафт)|\blink\b",
       "Minecraft-ник меняется в разделе «Ещё → Minecraft-ник» (/link).", "🔗 Minecraft-ник", "menu:link"),
    _s("mcauth", r"java auth|авторизац|пароль на сервер|регистрац.*сервер|/login|/register",
       "Вход на сервер для Java настраивается в разделе «Ещё → Java Auth».", "🔐 Java Auth", "player:mc_auth"),
    _s("mccmds", r"команд.*(майнкрафт|minecraft|сервер|игр)|как телепорт|\bтпа\b|/home|/tpa|\bдом\b",
       "Команды, которые работают на сервере, — раздел «Ещё → Команды Minecraft».", "📚 Команды Minecraft", "player:minecraft_commands"),
    _s("notifications", r"уведомлен", "Уведомления включаются и выключаются в разделе «Уведомления».", "🔔 Уведомления", "player:notifications"),
    _s("profile", r"профил|мой статус|статус заявк|одобрил|приняли|когда ответ",
       "Ваш профиль и статус заявки — в разделе «Профиль».", "👤 Профиль", "profile", "profile"),
    _s("help", r"что (ты )?умеешь|список команд|команды бота|чем помочь|помощь",
       "Все команды бота по разделам — в «Помощи».", "❓ Помощь", "menu:help", "menu:help"),
)


def match_sections(question: str) -> list[Section]:
    text = question or ""
    return [section for section in SECTIONS if section.pattern.search(text)]


def _callback(section: Section, accepted: bool) -> str | None:
    return section.member_cb if accepted else section.guest_cb


def build_answer(question: str, status: str) -> tuple[str, InlineKeyboardMarkup] | None:
    """Return (text, buttons) for the best-matching sections, or None when nothing matches."""
    matched = match_sections(question)
    if not matched:
        return None
    accepted = status == "ACCEPTED"
    available = [s for s in matched if _callback(s, accepted)]
    if not available:
        apply_row = [InlineKeyboardButton(text="📝 Подать заявку", callback_data="apply"),
                     InlineKeyboardButton(text="🧭 Что дальше?", callback_data="guide")]
        return ("🔒 Этот раздел открывается после одобрения заявки.", InlineKeyboardMarkup(inline_keyboard=[apply_row]))
    text = available[0].hint
    buttons = [InlineKeyboardButton(text=s.label, callback_data=_callback(s, accepted)) for s in available[:4]]
    rows = [buttons[i:i + 2] for i in range(0, len(buttons), 2)]
    return text, InlineKeyboardMarkup(inline_keyboard=rows)
