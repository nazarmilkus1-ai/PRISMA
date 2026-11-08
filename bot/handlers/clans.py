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
        "<code>/clan join &lt;название&gt;</code> — вступить в открытый клан.\n"
        "<code>/clan leave</code> — покинуть клан.\n"
        "<code>/clan disband</code> — распустить свой клан.\n"
        "<code>/clan invite &lt;Minecraft-ник&gt;</code> — пригласить игрока.\n"
        "<code>/clan invites</code> — входящие приглашения.\n"
        "<code>/clan accept &lt;ID&gt;</code> — принять приглашение.\n"
        "<code>/clan deny &lt;ID&gt;</code> — отклонить приглашение.\n"
        "<code>/clan role &lt;ник&gt; &lt;роль&gt;</code> — изменить роль.\n"
        "<code>/clan announce &lt;заголовок&gt; | &lt;текст&gt;</code> — объявление клана.\n"
        "<code>/clan cancel-invite &lt;ID&gt;</code> — отменить своё приглашение.\n"
        "<code>/clan history</code> — история действий клана.\n"
        "<code>/clan achievements</code> — достижения клана.\n\n"
        "Роли: <code>совладелец</code>, <code>офицер</code>, <code>участник</code>, <code>рекрут</code>."
    )


async def _show_info(message: types.Message, tg_id: int):
    result = await bot_get_clan_info(tg_id)
    if result.error:
        await message.answer("❌ Не удалось получить данные клана.")
        return
    if isinstance(result.data, dict) and result.data.get("error") == "NO_CLAN":
        await message.answer("⚔️ Вы не состоите в клане. Используйте <code>/clan create</code> или <code>/clan list</code>.", parse_mode="HTML")
        return
    if not isinstance(result.data, dict):
        await message.answer("❌ Некорректный ответ БД.")
        return

    data = result.data
    members = data.get("members") or []
    lines = [
        f"⚔️ <b>[{escape(str(data.get('tag') or '—'))}] {escape(str(data.get('name') or 'Клан'))}</b>",
        f"Уровень: <b>{data.get('level', 1)}</b> · XP: <b>{data.get('xp', 0)}</b>",
        f"Рейтинг: <b>{data.get('rating', 0)}</b> · Победы/поражения: <b>{data.get('wins', 0)}/{data.get('losses', 0)}</b>",
        f"Участников: <b>{len(members)}</b>",
    ]
    description = str(data.get("description") or "").strip()
    if description:
        lines.append(f"\n{escape(description)}")
    lines.append("\n<b>Состав:</b>")
    for member in members[:20]:
        nickname = member.get("minecraft_nick") or member.get("full_name") or member.get("tg_id") or "Игрок"
        role = ROLE_LABELS.get(str(member.get("role") or ""), str(member.get("role") or "Участник"))
        lines.append(f"• <code>{escape(str(nickname))}</code> — {escape(role)}")
    if len(members) > 20:
        lines.append(f"• и ещё {len(members) - 20}")

    await message.answer("\n".join(lines), parse_mode="HTML")


async def _list_clans(message: types.Message):
    result = await bot_list_clans()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список кланов.")
        return
    if not result.data:
        await message.answer("⚔️ Активных кланов пока нет.")
        return

    lines = ["⚔️ <b>Кланы PRISMA</b>"]
    for index, clan in enumerate(result.data[:20], 1):
        tag = escape(str(clan.get("tag") or "—"))
        name = escape(str(clan.get("name") or "Клан"))
        lines.append(
            f"{index}. <b>[{tag}] {name}</b> · ур. {clan.get('level', 1)} · "
            f"рейтинг {clan.get('rating', 0)} · {clan.get('wins', 0)}/{clan.get('losses', 0)}"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")


async def _list_invites(message: types.Message, tg_id: int):
    result = await bot_list_clan_invites(tg_id)
    if result.error:
        await message.answer(f"❌ {_error(result, 'Не удалось получить приглашения.')}", parse_mode="HTML")
        return

    invites = result.data.get("invites", []) if isinstance(result.data, dict) else result.data
    if not isinstance(invites, list) or not invites:
        await message.answer("📨 Активных приглашений нет.")
        return

    lines = ["📨 <b>Приглашения в кланы</b>"]
    for invite in invites[:10]:
        clan = f"[{invite.get('tag') or '—'}] {invite.get('name') or 'Клан'}"
        inviter = invite.get("inviter_nickname") or "Игрок"
        invite_id = str(invite.get("id") or "—")
        lines.append(
            f"• <b>{escape(str(clan))}</b> · от <code>{escape(str(inviter))}</code>\n"
            f"  ID: <code>{escape(invite_id)}</code>"
        )
    lines.append("\nПринять: <code>/clan accept &lt;ID&gt;</code>")
    lines.append("Отклонить: <code>/clan deny &lt;ID&gt;</code>")
    await message.answer("\n".join(lines), parse_mode="HTML")


async def _show_history(message: types.Message, tg_id: int):
    result = await bot_get_clan_activity(tg_id)
    if result.error:
        await message.answer(f"❌ {_error(result, 'Не удалось получить историю клана.')}", parse_mode="HTML")
        return

    rows = result.data if isinstance(result.data, list) else []
    if not rows:
        await message.answer("📜 История клана пока пуста.")
        return

    labels = {
        "CLAN_CREATED": "Клан создан",
        "MEMBER_JOIN": "Участник вступил",
        "MEMBER_LEAVE": "Участник вышел",
        "ROLE_CHANGE": "Изменена роль",
        "MEMBER_MOVED": "Участник переведён",
        "INVITE_SENT": "Отправлено приглашение",
        "INVITE_ACCEPTED": "Приглашение принято",
        "INVITE_DECLINED": "Приглашение отклонено",
        "INVITE_CANCELLED": "Приглашение отменено",
        "INVITE_EXPIRED": "Приглашение истекло",
        "ANNOUNCEMENT_CREATED": "Опубликовано объявление",
        "ANNOUNCEMENT_DELETED": "Удалено объявление",
        "VILLAGE_CREATED": "Создана территория",
        "VILLAGE_DELETED": "Удалена территория",
        "WAR_DECLARED": "Объявлена война",
        "WAR_ACTIVE": "Война началась",
        "WAR_FINISHED": "Война завершена",
        "WAR_CANCELLED": "Война отменена",
    }

    lines = ["📜 <b>История клана</b>"]
    for row in rows[:15]:
        kind = labels.get(str(row.get("kind") or ""), str(row.get("kind") or "Событие"))
        actor = row.get("nickname") or "Система PRISMA"
        payload = row.get("payload") or {}
        detail = ""
        if str(row.get("kind")) == "ROLE_CHANGE":
            detail = f" · {ROLE_LABELS.get(payload.get('old_role'), payload.get('old_role', '—'))} → {ROLE_LABELS.get(payload.get('role'), payload.get('role', '—'))}"
        elif str(row.get("kind")) in {"ANNOUNCEMENT_CREATED", "ANNOUNCEMENT_DELETED"}:
            detail = f" · {payload.get('title') or 'объявление'}"
        elif str(row.get("kind")) in {"VILLAGE_CREATED", "VILLAGE_DELETED"}:
            detail = f" · {payload.get('name') or 'территория'}"
        elif str(row.get("kind")) == "WAR_FINISHED":
            detail = f" · {payload.get('score_for', 0)}:{payload.get('score_against', 0)}"

        lines.append(
            f"• <b>{escape(kind)}</b> — <code>{escape(str(actor))}</code>{escape(detail)}"
        )

    await message.answer("\n".join(lines), parse_mode="HTML")


async def _show_achievements(message: types.Message, tg_id: int):
    result = await bot_get_clan_achievements(tg_id)
    if result.error:
        await message.answer(f"❌ {_error(result, 'Не удалось получить достижения клана.')}", parse_mode="HTML")
        return

    rows = result.data if isinstance(result.data, list) else []
    if not rows:
        await message.answer("🏆 <b>Достижения клана</b>\n\nПока ничего не открыто.", parse_mode="HTML")
        return

    lines = ["🏆 <b>Достижения клана</b>"]
    for row in rows[:15]:
        title = row.get("title") or "Достижение"
        description = row.get("description") or ""
        reward = row.get("xp_reward", 0)
        lines.append(
            f"\n{escape(str(row.get('icon') or '🏆'))} <b>{escape(str(title))}</b>"
            f"\n{escape(str(description))}"
            f"\n+{reward} XP · {escape(str(row.get('unlocked_at') or ''))}"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")


async def _set_role(message: types.Message, tg_id: int, args: list[str]):
    if len(args) != 3:
        await message.answer("❌ Использование: <code>/clan role &lt;ник&gt; &lt;роль&gt;</code>", parse_mode="HTML")
        return

    role = ROLE_ALIASES.get(args[2].lower())
    if not role:
        await message.answer("❌ Неизвестная роль. Используйте: совладелец, офицер, участник или рекрут.")
        return

    result = await bot_set_clan_role(tg_id, args[1], role)
    if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
        await message.answer(f"❌ {_error(result)}", parse_mode="HTML")
        return

    label = ROLE_LABELS.get(role, role)
    await message.answer(
        f"✅ Роль <code>{escape(args[1])}</code> изменена на <b>{escape(label)}</b>.",
        parse_mode="HTML",
    )


@router.message(Command("clan"))
async def cmd_clan(message: types.Message, state: FSMContext):
    if not await is_approved(message.from_user.id):
        await message.answer(DENIED_MESSAGE)
        return

    parts = (message.text or "").split()
    args = parts[1:]
    sub = args[0].lower() if args else ""

    if not sub:
        await _show_info(message, message.from_user.id)
        return

    if sub in {"help", "помощь"}:
        await message.answer(_help_text(), parse_mode="HTML")
        return

    if sub in {"create", "создать"}:
        await state.set_state(ClanForm.waiting_name)
        await message.answer("⚔️ Введите название клана (2–32 символа) или /cancel.")
        return

    if sub in {"list", "список"}:
        await _list_clans(message)
        return

    if sub in {"join", "вступить"}:
        if len(args) < 2:
            await message.answer("❌ Использование: <code>/clan join &lt;название&gt;</code>", parse_mode="HTML")
            return
        result = await bot_join_clan(message.from_user.id, " ".join(args[1:]))
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result)}", parse_mode="HTML")
            return
        await message.answer(
            f"✅ Вы вступили в клан <b>[{escape(str(result.data.get('tag') or '—'))}] {escape(str(result.data.get('name') or 'Клан'))}</b>.",
            parse_mode="HTML",
        )
        return

    if sub in {"leave", "покинуть"}:
        result = await bot_leave_clan(message.from_user.id)
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result)}", parse_mode="HTML")
            return
        if isinstance(result.data, dict) and result.data.get("disbanded"):
            await message.answer("✅ Клан расформирован.")
        else:
            await message.answer("✅ Вы покинули клан.")
        return

    if sub in {"disband", "распустить"}:
        result = await bot_disband_clan(message.from_user.id)
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result)}", parse_mode="HTML")
            return
        await message.answer("✅ Клан распущен.", parse_mode="HTML")
        return

    if sub in {"invite", "пригласить"}:
        if len(args) != 2:
            await message.answer("❌ Использование: <code>/clan invite &lt;Minecraft-ник&gt;</code>", parse_mode="HTML")
            return
        result = await bot_clan_invite(message.from_user.id, args[1])
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result, 'Не удалось отправить приглашение.')}", parse_mode="HTML")
            return
        await message.answer(f"✅ Приглашение игроку <code>{escape(args[1])}</code> отправлено.", parse_mode="HTML")
        return

    if sub in {"invites", "заявки", "приглашения"}:
        await _list_invites(message, message.from_user.id)
        return

    if sub in {"accept", "принять"}:
        if len(args) != 2:
            await message.answer("❌ Использование: <code>/clan accept &lt;ID&gt;</code>", parse_mode="HTML")
            return
        result = await bot_accept_clan_invite(message.from_user.id, args[1])
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result, 'Не удалось принять приглашение.')}", parse_mode="HTML")
            return
        await message.answer(
            f"✅ Вы вступили в клан <b>[{escape(str(result.data.get('tag') or '—'))}] {escape(str(result.data.get('name') or 'Клан'))}</b>.",
            parse_mode="HTML",
        )
        return

    if sub in {"deny", "отклонить", "decline"}:
        if len(args) != 2:
            await message.answer("❌ Использование: <code>/clan deny &lt;ID&gt;</code>", parse_mode="HTML")
            return
        result = await bot_decline_clan_invite(message.from_user.id, args[1])
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result, 'Не удалось отклонить приглашение.')}", parse_mode="HTML")
            return
        await message.answer("✅ Приглашение отклонено.")
        return

    if sub in {"role", "роль", "назначить"}:
        await _set_role(message, message.from_user.id, args)
        return

    if sub in {"announce", "объявление", "объявить"}:
        raw = (message.text or "").split(maxsplit=2)
        payload = raw[2] if len(raw) >= 3 else ""
        if "|" not in payload:
            await message.answer("❌ Использование: <code>/clan announce Заголовок | Текст</code>", parse_mode="HTML")
            return
        title, body = [part.strip() for part in payload.split("|", 1)]
        if not 3 <= len(title) <= 120 or not 3 <= len(body) <= 3000:
            await message.answer("❌ Заголовок: 3–120 символов, текст: 3–3000 символов.")
            return
        result = await bot_create_clan_announcement(message.from_user.id, title, body)
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result, 'Не удалось опубликовать объявление.')}", parse_mode="HTML")
            return
        await message.answer(f"✅ Объявление <b>{escape(title)}</b> опубликовано.", parse_mode="HTML")
        return

    if sub in {"cancel-invite", "cancel_invite", "отменить-приглашение"}:
        if len(args) != 2:
            await message.answer("❌ Использование: <code>/clan cancel-invite &lt;ID&gt;</code>", parse_mode="HTML")
            return
        result = await bot_cancel_clan_invite(message.from_user.id, args[1])
        if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
            await message.answer(f"❌ {_error(result, 'Не удалось отменить приглашение.')}", parse_mode="HTML")
            return
        await message.answer("✅ Приглашение отменено.")
        return

    if sub in {"history", "история", "история_клана"}:
        await _show_history(message, message.from_user.id)
        return

    if sub in {"achievements", "достижения"}:
        await _show_achievements(message, message.from_user.id)
        return

    await message.answer(_help_text(), parse_mode="HTML")


@router.message(StateFilter(ClanForm.waiting_name))
async def create_clan(message: types.Message, state: FSMContext):
    name = (message.text or "").strip()
    if not 2 <= len(name) <= 32:
        await message.answer("❌ Название должно содержать 2–32 символа.")
        return
    result = await bot_create_clan(message.from_user.id, name)
    if result.error or not (isinstance(result.data, dict) and result.data.get("success")):
        await message.answer(f"❌ {_error(result, 'Не удалось создать клан.')}", parse_mode="HTML")
        return
    await state.clear()
    await message.answer(
        f"✅ Клан <b>[{escape(str(result.data.get('tag') or '—'))}] {escape(name)}</b> создан!",
        parse_mode="HTML",
    )


@router.message(Command("cancel"), StateFilter(ClanForm))
async def cancel_clan(message: types.Message, state: FSMContext):
    await state.clear()
    await message.answer("❌ Отменено.")
