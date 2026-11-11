"""Staff panel keyboards. Sections are shown from the staff permission list when it is known;
every click re-checks the permission server-side, so hiding a button is only convenience."""
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup


def _can(perms, key: str) -> bool:
    return perms is None or "*" in perms or key in perms


def _btn(text: str, data: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(text=text, callback_data=data)


def _badge(label: str, count) -> str:
    return f"{label} ({count})" if count else label


def _rows(buttons: list[InlineKeyboardButton]) -> list[list[InlineKeyboardButton]]:
    return [buttons[i:i + 2] for i in range(0, len(buttons), 2)]


def home_keyboard(snap: dict | None = None, perms=None, panel_url: str | None = None) -> InlineKeyboardMarkup:
    snap = snap or {}
    queues: list[InlineKeyboardButton] = []
    if _can(perms, "application.view"):
        queues.append(_btn(_badge("📋 Заявки", snap.get("applications")), "admin:applications"))
    if _can(perms, "report.view"):
        queues.append(_btn(_badge("📢 Репорты", snap.get("reports")), "admin:reports"))
    if _can(perms, "appeal.view"):
        queues.append(_btn(_badge("⚖️ Апелляции", snap.get("appeals")), "admin:appeals"))
    if _can(perms, "player.view"):
        queues.append(_btn(_badge("🆘 Поддержка", snap.get("support")), "ap:support"))
    rows = _rows(queues)
    sections: list[InlineKeyboardButton] = []
    if _can(perms, "player.view"):
        sections.append(_btn("👥 Люди", "ap:people"))
    if _can(perms, "punishment.view_history"):
        sections.append(_btn("🛡 Модерация", "ap:mod"))
    if _can(perms, "system.health"):
        sections.append(_btn("🖥 Система", "ap:sys"))
    sections.append(_btn("🤖 PRISMA_AGENT", "ai:admin"))
    rows += _rows(sections)
    rows.append([_btn("🔄 Обновить", "ap:home")])
    if panel_url:
        rows.append([InlineKeyboardButton(text="🌐 Войти в Prisma Panel", url=panel_url)])
    rows.append([_btn("👤 Режим участника", "mode:participant")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def back_row() -> list[InlineKeyboardButton]:
    return [_btn("⬅️ В панель", "ap:home")]


def section_keyboard(section: str, perms=None, panel_url: str | None = None) -> InlineKeyboardMarkup:
    buttons: list[InlineKeyboardButton] = []
    if section == "people":
        buttons = [_btn("🔎 Найти игрока", "ap:find"), _btn("🟢 Сейчас онлайн", "ap:online"),
                   _btn("💤 Неактивные 7 дней", "ap:inactive"), _btn("👮 Персонал", "ap:staff")]
    elif section == "mod":
        if _can(perms, "report.view"):
            buttons.append(_btn("📢 Репорты", "admin:reports"))
        if _can(perms, "appeal.view"):
            buttons.append(_btn("⚖️ Апелляции", "admin:appeals"))
        if _can(perms, "automod.view"):
            buttons.append(_btn("🤖 Автомод", "admin:automod"))
        buttons.append(_btn("⌨️ Команды наказаний", "admin:moderation"))
    elif section == "sys":
        buttons = [_btn("🖥 Сервер", "ap:server"), _btn("⚠️ Ошибки бота", "ap:errors")]
        if _can(perms, "automod.view"):
            buttons.append(_btn("🤖 Автомод", "admin:automod"))
        if panel_url:
            buttons.append(InlineKeyboardButton(text="🌐 Prisma Panel", url=panel_url))
    rows = _rows(buttons)
    rows.append(back_row())
    return InlineKeyboardMarkup(inline_keyboard=rows)
