from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

APPLICATION_DISCOVERY_SOURCES = ("Telegram", "TikTok", "YouTube", "Discord", "Рекомендация друга", "Другое")


def _with_mode_switch(rows, show_admin_switch: bool):
    if show_admin_switch:
        rows.append([
            InlineKeyboardButton(
                text="🛡 Режим администратора",
                callback_data="mode:admin",
            )
        ])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def _wiki_button():
    from config import SITE_URL
    return InlineKeyboardButton(text="📚 Wiki", url=f"{SITE_URL}/wiki")


def main_menu_before_apply(show_admin_switch: bool = False):
    rows = [
        [InlineKeyboardButton(text="📝 Подать заявку", callback_data="apply"),
         InlineKeyboardButton(text="🧭 Что дальше?", callback_data="guide")],
        [InlineKeyboardButton(text="🌐 Сервер", callback_data="about_server"),
         InlineKeyboardButton(text="📰 Новости", callback_data="news")],
        [InlineKeyboardButton(text="📖 О PRISMA", callback_data="about_prisma"),
         InlineKeyboardButton(text="📜 Правила", callback_data="rules")],
        [_wiki_button(),
         InlineKeyboardButton(text="🤖 Спросить", callback_data="ask")],
        [InlineKeyboardButton(text="❓ Помощь", callback_data="menu:help")],
    ]
    return _with_mode_switch(rows, show_admin_switch)


def onboarding_group_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🤖 Открыть бота PRISMA", url="https://t.me/prisma_eco_bot?start=onboarding")],
    ])


def main_menu_pending(show_admin_switch: bool = False):
    rows = [
        [InlineKeyboardButton(text="⏳ Статус заявки", callback_data="profile"),
         InlineKeyboardButton(text="🧭 Что дальше?", callback_data="guide")],
        [InlineKeyboardButton(text="🌐 Сервер", callback_data="about_server"),
         InlineKeyboardButton(text="📰 Новости", callback_data="news")],
        [InlineKeyboardButton(text="📖 О PRISMA", callback_data="about_prisma"),
         InlineKeyboardButton(text="📜 Правила", callback_data="rules")],
        [_wiki_button(),
         InlineKeyboardButton(text="🤖 Спросить", callback_data="ask")],
        [InlineKeyboardButton(text="❓ Помощь", callback_data="menu:help")],
    ]
    return _with_mode_switch(rows, show_admin_switch)


def main_menu_approved(show_admin_switch: bool = False):
    rows = [
        [InlineKeyboardButton(text="👤 Профиль", callback_data="profile"),
         InlineKeyboardButton(text="🖥 Сервер", callback_data="player:server")],
        [InlineKeyboardButton(text="🏅 Топ", callback_data="player:top"),
         InlineKeyboardButton(text="🎯 Ивенты", callback_data="player:events")],
        [InlineKeyboardButton(text="⚔️ Кланы", callback_data="clans"),
         InlineKeyboardButton(text="🛒 Рынок", callback_data="market")],
        [InlineKeyboardButton(text="📰 Новости", callback_data="news"),
         InlineKeyboardButton(text="🗳 Голосования", callback_data="polls")],
        [InlineKeyboardButton(text="📢 Жалоба", callback_data="reports"),
         InlineKeyboardButton(text="🆘 Поддержка", callback_data="support")],
        [InlineKeyboardButton(text="🔔 Уведомления", callback_data="player:notifications"),
         InlineKeyboardButton(text="➕ Ещё", callback_data="menu:player")],
    ]
    return _with_mode_switch(rows, show_admin_switch)


def player_menu_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👤 Профиль", callback_data="profile"),
         InlineKeyboardButton(text="📊 Статистика", callback_data="player:stats")],
        [InlineKeyboardButton(text="🏆 Достижения", callback_data="player:achievements"),
         InlineKeyboardButton(text="🏅 Топ", callback_data="player:top")],
        [InlineKeyboardButton(text="⚔️ Player Battle", callback_data="player:battles")],
        [InlineKeyboardButton(text="📚 Команды Minecraft", callback_data="player:minecraft_commands")],
        [InlineKeyboardButton(text="🔗 Minecraft-ник", callback_data="menu:link"),
         InlineKeyboardButton(text="🔐 Java Auth", callback_data="player:mc_auth")],
        [InlineKeyboardButton(text="↩️ Назад", callback_data="menu:back")],
    ])


def community_menu_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🎯 Ивенты", callback_data="player:events"),
         InlineKeyboardButton(text="⭐ Оценить сервер", callback_data="player:rate")],
        [InlineKeyboardButton(text="💎 Оценить PRISMA", callback_data="player:prisma_rating"),
         InlineKeyboardButton(text="🆘 Поддержка", callback_data="support")],
        [InlineKeyboardButton(text="⚔️ Кланы", callback_data="clans"),
         InlineKeyboardButton(text="📰 Новости", callback_data="news")],
        [InlineKeyboardButton(text="🗳 Голосования", callback_data="polls"),
         InlineKeyboardButton(text="🛒 Рынок", callback_data="market")],
        [InlineKeyboardButton(text="↩️ Назад", callback_data="menu:back")],
    ])


def moderation_menu_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📢 Создать жалобу", callback_data="reports"),
         InlineKeyboardButton(text="📋 Мои жалобы", callback_data="player:reports")],
        [InlineKeyboardButton(text="⚠️ Наказания", callback_data="player:punishments"),
         InlineKeyboardButton(text="⚖️ Апелляции", callback_data="player:appeals")],
        [InlineKeyboardButton(text="↩️ Назад", callback_data="menu:back")],
    ])


def player_center_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📊 Статистика", callback_data="player:stats"),
         InlineKeyboardButton(text="🏆 Достижения", callback_data="player:achievements")],
        [InlineKeyboardButton(text="🏅 Топ игроков", callback_data="player:top"),
         InlineKeyboardButton(text="⚖️ Наказания", callback_data="player:punishments")],
        [InlineKeyboardButton(text="📋 Мои жалобы", callback_data="player:reports"),
         InlineKeyboardButton(text="📝 Апелляции", callback_data="player:appeals")],
        [InlineKeyboardButton(text="🎯 Ивенты", callback_data="player:events"),
         InlineKeyboardButton(text="🖥 Сервер", callback_data="player:server")],
        [InlineKeyboardButton(text="⚔️ Player Battle", callback_data="player:battles")],
        [InlineKeyboardButton(text="🔔 Уведомления", callback_data="player:notifications"),
         InlineKeyboardButton(text="⚔️ Клан", callback_data="player:clan")],
    ])


def admin_menu(panel_url: str | None = None):
    rows = [
        [InlineKeyboardButton(text="📋 Заявки", callback_data="admin:applications"),
         InlineKeyboardButton(text="📢 Репорты", callback_data="admin:reports")],
        [InlineKeyboardButton(text="⚖️ Апелляции", callback_data="admin:appeals"),
         InlineKeyboardButton(text="🤖 Автомод", callback_data="admin:automod")],
        [InlineKeyboardButton(text="👥 Игроки", callback_data="admin:players"),
         InlineKeyboardButton(text="🖥 Сервер", callback_data="admin:server")],
        [InlineKeyboardButton(text="🛡 Модерация", callback_data="admin:moderation"),
         InlineKeyboardButton(text="🤖 Copilot", callback_data="ai:admin")],
    ]
    if panel_url:
        rows.append([InlineKeyboardButton(text="🌐 Открыть Prisma Panel", url=panel_url)])
    rows.append([InlineKeyboardButton(text="👤 Режим участника", callback_data="mode:participant")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


def notification_keyboard(prefs: dict):
    def mark(key: str) -> str:
        return "✅" if prefs.get(key, True) else "☑️"
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"{mark('news')} Новости", callback_data="notify:news"),
         InlineKeyboardButton(text=f"{mark('events')} Ивенты", callback_data="notify:events"),
         InlineKeyboardButton(text=f"{mark('server_status')} Сервер", callback_data="notify:server_status")],
        [InlineKeyboardButton(text=f"{mark('clan_news')} Клан", callback_data="notify:clan_news"),
         InlineKeyboardButton(text=f"{mark('social')} Соц. запросы", callback_data="notify:social"),
         InlineKeyboardButton(text=f"{mark('battles')} Battle", callback_data="notify:battles")],
        [InlineKeyboardButton(text=f"{mark('market')} Рынок", callback_data="notify:market"),
         InlineKeyboardButton(text=f"{mark('moderation')} Модерация", callback_data="notify:moderation"),
         InlineKeyboardButton(text=f"{mark('polls')} Голосования", callback_data="notify:polls")],
    ])


def event_keyboard(event_id: str, registered: bool = False):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(
            text="❌ Отменить регистрацию" if registered else "✅ Участвовать",
            callback_data=f"event:unreg:{event_id}" if registered else f"event:reg:{event_id}",
        )],
    ])


def appeal_keyboard(punishment_id: str):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⚖️ Подать апелляцию", callback_data=f"appeal:{punishment_id}")],
    ])


def agreement_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="✅ Да", callback_data="agree_yes"),
         InlineKeyboardButton(text="❌ Нет", callback_data="agree_no")],
    ])


def platform_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="☕ Java", callback_data="platform_java"),
         InlineKeyboardButton(text="🧱 Bedrock", callback_data="platform_bedrock")],
    ])


def discovery_source_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=source, callback_data=f"discovery:{index}")] for index, source in enumerate(APPLICATION_DISCOVERY_SOURCES)])

def preview_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="✅ Подтвердить", callback_data="confirm")],
        [InlineKeyboardButton(text="✏️ Редактировать", callback_data="edit"),
         InlineKeyboardButton(text="❌ Отменить", callback_data="cancel")],
    ])


def poll_keyboard(poll_id: str, options: list):
    from utils.uuid_helpers import encode_uuid
    encoded_poll = encode_uuid(poll_id)
    buttons = []
    for opt in options:
        encoded_option = encode_uuid(str(opt["id"]))
        buttons.append([InlineKeyboardButton(
            text=f"{opt['position']}. {opt['text']}",
            callback_data=f"v:{encoded_poll}:{encoded_option}",
        )])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def rating_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=f"{i}★", callback_data=f"server_rating:{i}") for i in range(1, 6)]])

def prisma_rating_keyboard():
    return InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=f"{i}★", callback_data=f"prisma_rating:{i}") for i in range(1, 6)]])

def social_request_keyboard(kind: str, request_id: str):
    prefix = "M" if str(kind).upper() == "MARRIAGE" else "R"
    return InlineKeyboardMarkup(inline_keyboard=[
        [
            InlineKeyboardButton(text="✅ Принять", callback_data=f"social:accept:{prefix}:{request_id}"),
            InlineKeyboardButton(text="❌ Отклонить", callback_data=f"social:reject:{prefix}:{request_id}"),
        ],
    ])

