from aiogram import Bot
from aiogram.types import (
    BotCommand,
    BotCommandScopeAllChatAdministrators,
    BotCommandScopeAllGroupChats,
    BotCommandScopeChat,
)


# Telegram shows this list in the "/" menu. Keep it short: the rest of the
# commands still work, they are just reachable from the buttons or /help.
PUBLIC_COMMANDS = [
    BotCommand(command="start", description="Главное меню"),
    BotCommand(command="profile", description="Мой профиль"),
    BotCommand(command="server", description="Состояние сервера"),
    BotCommand(command="top", description="Топ игроков"),
    BotCommand(command="events", description="Ивенты"),
    BotCommand(command="clan", description="Мой клан"),
    BotCommand(command="market", description="Рынок"),
    BotCommand(command="news", description="Новости"),
    BotCommand(command="report", description="Подать жалобу"),
    BotCommand(command="support", description="Поддержка"),
    BotCommand(command="ask", description="Спросить помощника"),
    BotCommand(command="guide", description="Что дальше? (пошаговый гайд)"),
    BotCommand(command="quick", description="Быстрые действия"),
    BotCommand(command="application", description="Подать заявку"),
    BotCommand(command="rules", description="Правила"),
    BotCommand(command="help", description="Все команды"),
]


# Visible to everyone in group chats. Only what is useful in a chat; everything else still works
# when typed, it just does not clutter the "/" menu.
GROUP_COMMANDS = [
    BotCommand(command="ai", description="Спросить PRISMA_AI"),
    BotCommand(command="server", description="Состояние сервера"),
    BotCommand(command="top", description="Топ активности чата"),
    BotCommand(command="stats", description="Статистика чата"),
    BotCommand(command="clan", description="Кланы"),
    BotCommand(command="wiki", description="Wiki PRISMA"),
    BotCommand(command="rules", description="Правила"),
    BotCommand(command="help", description="Команды чата"),
]


# Extra commands shown only to chat administrators.
GROUP_ADMIN_COMMANDS = GROUP_COMMANDS + [
    BotCommand(command="warn", description="Предупреждение"),
    BotCommand(command="mute", description="Мут"),
    BotCommand(command="ban", description="Бан"),
    BotCommand(command="kick", description="Кик"),
    BotCommand(command="unmute", description="Снять мут"),
    BotCommand(command="unban", description="Снять бан"),
    BotCommand(command="unwarn", description="Снять варн"),
    BotCommand(command="warns", description="Варны"),
    BotCommand(command="inactive", description="Кто неактивен"),
    BotCommand(command="ai_chat", description="PRISMA_AI в чате: вкл/выкл"),
]


ADMIN_COMMANDS = GROUP_COMMANDS + [
    BotCommand(command="warn", description="Варн"),
    BotCommand(command="mute", description="Мут"),
    BotCommand(command="ban", description="Бан"),
    BotCommand(command="kick", description="Кик"),
    BotCommand(command="unmute", description="Размут"),
    BotCommand(command="unban", description="Разбан"),
    BotCommand(command="unwarn", description="Снять варн"),
    BotCommand(command="warns", description="Варны"),
    BotCommand(command="onboarding", description="Позвать на вступление"),
    BotCommand(command="moderator", description="Назначить staff"),
]


ADMIN_COMMANDS = PUBLIC_COMMANDS + [
    BotCommand(command="onboarding", description="Позвать на вступление"),
    BotCommand(command="admin", description="Админ-панель"),
    BotCommand(command="ai", description="PRISMA_AGENT: задачи для админа"),
    BotCommand(command="ai_status", description="Проверка связи с ИИ"),
    BotCommand(command="players", description="Поиск игроков"),
    BotCommand(command="app_approve", description="Одобрить заявку"),
    BotCommand(command="app_reject", description="Отклонить заявку"),
    BotCommand(command="report_status", description="Изменить статус репорта"),
    BotCommand(command="appeal_review", description="Взять апелляцию в работу"),
    BotCommand(command="appeal_approve", description="Одобрить апелляцию"),
    BotCommand(command="appeal_reject", description="Отклонить апелляцию"),
    BotCommand(command="warn", description="Выдать предупреждение"),
    BotCommand(command="mute", description="Выдать мут"),
    BotCommand(command="ban", description="Выдать бан"),
    BotCommand(command="kick", description="Кикнуть игрока"),
    BotCommand(command="unban", description="Снять бан"),
    BotCommand(command="unmute", description="Снять мут"),
    BotCommand(command="unwarn", description="Снять предупреждение"),
    BotCommand(command="history", description="История наказаний"),
    BotCommand(command="poll_create", description="Создать голосование"),
    BotCommand(command="support_list", description="Обращения в поддержку"),
    BotCommand(command="support_resolve", description="Закрыть обращение"),
    BotCommand(command="finish_poll", description="Завершить голосование"),
]


async def set_group_commands(bot: Bot) -> None:
    await bot.set_my_commands(
        GROUP_COMMANDS,
        scope=BotCommandScopeAllGroupChats(),
    )
    await bot.set_my_commands(
        GROUP_ADMIN_COMMANDS,
        scope=BotCommandScopeAllChatAdministrators(),
    )


async def set_user_commands(bot: Bot, tg_id: int, admin: bool) -> None:
    commands = ADMIN_COMMANDS if admin else PUBLIC_COMMANDS
    await bot.set_my_commands(
        commands,
        scope=BotCommandScopeChat(chat_id=tg_id),
    )
