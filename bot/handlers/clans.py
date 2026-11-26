from html import escape

from aiogram import Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext

from db.rpc import (
    bot_accept_clan_invite,
    bot_cancel_clan_invite,
    bot_clan_invite,
    bot_create_clan_announcement,
    bot_create_clan,
    bot_get_clan_activity,
    bot_get_clan_achievements,
    bot_decline_clan_invite,
    bot_disband_clan,
    bot_get_clan_info,
    bot_join_clan,
    bot_leave_clan,
    bot_list_clan_invites,
    bot_list_clans,
    bot_set_clan_role,
)
from fsm.states import ClanForm
from utils.permissions import DENIED_MESSAGE, is_approved

router = Router()

ROLE_ALIASES = {
    "совладелец": "co_owner",
    "заместитель": "co_owner",
    "co_owner": "co_owner",
    "co-owner": "co_owner",
    "офицер": "officer",
    "officer": "officer",
    "участник": "member",
    "member": "member",
    "рекрут": "recruit",
    "recruit": "recruit",
}

ROLE_LABELS = {
    "owner": "Владелец",
    "co_owner": "Совладелец",
    "officer": "Офицер",
    "member": "Участник",
    "recruit": "Рекрут",
}

ERRORS = {
    "USER_NOT_FOUND": "Пользователь не найден.",
    "USER_NOT_ALLOWED": "Действие недоступно для этого аккаунта.",
    "NO_CLAN": "Вы не состоите в клане.",
    "USER_ALREADY_IN_CLAN": "Вы уже состоите в клане.",
    "CLAN_NOT_FOUND": "Клан не найден.",
    "CLAN_NOT_OPEN": "Этот клан не принимает новых участников.",
    "NO_CLAN_PERMISSION": "Недостаточно прав в клане.",
    "OWNER_ONLY": "Это действие доступно только владельцу клана.",
    "PLAYER_NOT_FOUND": "Игрок не найден.",
    "PLAYER_ALREADY_IN_CLAN": "Игрок уже состоит в клане.",
    "INVITE_ALREADY_EXISTS": "Этому игроку уже отправлено приглашение.",
    "INVITE_NOT_FOUND": "Приглашение не найдено или уже недействительно.",
    "CANNOT_INVITE_SELF": "Нельзя пригласить самого себя.",
    "CANNOT_MANAGE_SELF": "Нельзя изменять собственную роль.",
    "TARGET_NOT_IN_CLAN": "Игрок не состоит в вашем клане.",
    "TARGET_INVALID_ROLE": "Нельзя управлять ролью равного или более высокого уровня.",
    "ROLE_UNCHANGED": "У игрока уже установлена эта роль.",
    "INVALID_ROLE": "Укажите корректную роль.",
}


def _error(result, fallback="Операция не выполнена."):
    code = str(result.error or "")
    if not code and isinstance(result.data, dict):
        code = str(result.data.get("error") or "")
    return ERRORS.get(code, fallback)


def _help_text():
    return (
        "⚔️ <b>PRISMA — кланы</b>\n\n"
        "<code>/clan</code> — мой клан и состав.\n"
        "<code>/clan create</code> — создать клан.\n"
        "<code>/clan list</code> — список кланов.\n"
        "<code>/clan join <название></code> — вступить в открытый клан.\n"
        "<code>/clan leave</code> — покинуть клан.\n"
        "<code>/clan disband</code> — распустить свой клан.\n"
        "<code>/clan invite <Minecraft-ник></code> — пригласить игрока.\n"
        "<code>/clan invites</code> — входящие приглашения.\n"
        "<code>/clan accept <ID></code> — принять приглашение.\n"
        "<code>/clan deny <ID></code> — отклонить приглашение.\n"
        "<code>/clan role <ник> <роль></code> — изменить роль.\n"
        "<code>/clan announce <заголовок> | <текст></code> — объявление клана.\n"
        "<code>/clan cancel-invite <ID></code> — отменить своё приглашение.\n"
        "<code>/clan history</code> — история действий клана.\n"
        "<code>/clan achievements</code> — достижения клана.\n\n"
        "Роли: <code>совладелец</code>, <code>офицер</code>, <code>участник</code>, <code>рекрут</code>."
    )


async def _show_info(message: types.Message, tg_id: int):
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для просмотра клана")
    if not valid:
        logger.warning("_show_info: invalid tg_id %s", tg_id)
        await message.answer("❌ Неверный Telegram ID.")
        return
    result = await bot_get_clan_info(tg_id)
