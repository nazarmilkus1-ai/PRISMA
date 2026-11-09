from __future__ import annotations

import random
import re
from datetime import datetime, timedelta, timezone

from aiogram import F, Router, types
from aiogram.filters import Command

from config import MODERATION_GROUP_ID
from utils.chat_permissions import muted_chat_permissions, unmuted_chat_permissions
from db.rpc import (
    bot_chat_top,
    bot_chat_stats,
    bot_chat_top_total,
    bot_list_current_participants,
    bot_create_chat_punishment,
    bot_create_clan,
    bot_find_user,
    bot_get_profile,
    bot_get_chat_mutes,
    bot_get_chat_warnings,
    bot_revoke_chat_punishment,
    bot_get_clan_info,
    bot_list_clans,
    bot_get_clan_by_position,
    bot_join_clan,
    bot_leave_clan,
    bot_disband_clan,
    bot_clan_invite,
    bot_set_clan_role,
    bot_list_clan_invites,
    bot_accept_clan_invite,
    bot_decline_clan_invite,
    bot_create_clan_announcement,
    bot_list_clan_wars,
    bot_create_clan_war,
    bot_respond_clan_war,
    bot_start_clan_war,
    bot_finish_clan_war,
    bot_lift_chat_punishment,
    bot_list_inactive_members,
    bot_active_chat_users,
    bot_touch_user,
    bot_check_admin_permission,
    bot_set_staff_role,
    bot_remove_staff,
    bot_list_staff,
    bot_list_marriages,
    bot_social_end,
    bot_social_info,
)
from handlers.social import handle_social, social_info_message
from aiogram.types import ChatPermissions
from utils.errors import safe_rpc_error
from utils.helpers import parse_duration
from services.community_membership import ensure_onboarding_restriction
from services.onboarding import deliver_onboarding_digest
from utils.permissions import require_admin_mode
from html import escape

router = Router()


@router.message(Command("onboarding"))
async def onboarding_digest_command(message: types.Message):
    # The command is accepted in DMs or the configured moderation group only.
    if message.chat.type != "private" and message.chat.id != MODERATION_GROUP_ID:
        return
    if not await require_admin_mode(message):
        return

    permission = await bot_check_admin_permission(message.from_user.id, "application.view")
    if permission.error or not permission.data:
        await message.answer("❌ Недостаточно прав для вызова участников.")
        return

    status, count = await deliver_onboarding_digest(message.bot, force=True)
    if status == "sent":
        await message.answer(
            f"✅ Список опубликован в группе модерации. Участников: {count}."
        )
    elif status == "empty":
        await message.answer("✅ Сейчас нет участников без поданной заявки.")
    elif status == "disabled":
        await message.answer("❌ Не настроена группа модерации.")
    else:
        await message.answer(
            "❌ Не удалось отправить список. Если обновление только что установлено, "
            "проверьте миграцию Supabase."
        )

MODERATION_ALIASES = {
    "warn": ("warn", "варн", "пред", "предупреждение"),
    "mute": ("mute", "мут", "заткнуть"),
    "ban": ("ban", "бан", "чс"),
    "kick": ("kick", "кик"),
    "unmute": ("unmute", "размут", "говори"),
    "unban": ("unban", "разбан", "вернуть"),
    "unwarn": ("unwarn", "снятьварн", "снять_варн"),
}

RP_ALIASES = {
    "обнять": "обнял(а)",
    "пожать": "пожал(а) руку",
    "датьпять": "дал(а) пять",
    "поддержать": "поддержал(а)",
}

def _is_prisma_chat(message: types.Message) -> bool:
    return bool(MODERATION_GROUP_ID and message.chat and message.chat.id == MODERATION_GROUP_ID)


def _first_line(text: str) -> tuple[list[str], str]:
    lines = (text or "").splitlines()
    first = lines[0] if lines else ""
    rest = "\n".join(lines[1:]).strip()
    try:
        tokens = first.split(maxsplit=1)
    except ValueError:
        tokens = [first]
    args = tokens[1].split() if len(tokens) == 2 else []
    return args, rest


_INACTIVE_WORDS = {
    "день": 1, "сутки": 1, "day": 1,
    "неделя": 7, "неделю": 7, "нед": 7, "week": 7,
    "месяц": 30, "мес": 30, "month": 30,
}


def _inactive_days(args: list[str], default: int) -> int:
    """Days of inactivity from '7', '7д', '1 неделя', 'неделя', 'месяц' (1..30)."""
    if not args:
        return default
    word = args[0].casefold()
    if word in _INACTIVE_WORDS:
        return _INACTIVE_WORDS[word]
    duration, _ = _duration_from_args(args)
    if duration:
        return max(1, min(30, duration // 86400))
    if word.isdigit():
        return max(1, min(30, int(word)))
    return default


def _days_label(days: int) -> str:
    if days == 7:
        return "неделю"
    if days == 30:
        return "месяц"
    return f"{days} {'день' if days == 1 else 'дн.'}"


def _duration_from_args(args: list[str]) -> tuple[int | None, list[str]]:
    if not args:
        return None, []

    # 10m / 10 минут / 2 часа / 1 неделя
    one = args[0]
    try:
        return parse_duration(one), args[1:]
    except ValueError:
        pass

    if len(args) >= 2:
        try:
            return parse_duration(f"{args[0]} {args[1]}"), args[2:]
        except ValueError:
            pass

    return None, args


async def _chat_admin(message: types.Message, need_restrict: bool = False) -> bool:
    if not _is_prisma_chat(message) or not message.from_user:
        return False
    try:
        member = await message.bot.get_chat_member(message.chat.id, message.from_user.id)
    except Exception:
        await message.answer("❌ Не удалось проверить ваши права в чате.")
        return False
    if getattr(member, "status", "") not in {"administrator", "creator"}:
        await message.answer("❌ Команда доступна только администраторам чата.")
        return False
    if need_restrict and not getattr(member, "can_restrict_members", False) and getattr(member, "status", "") != "creator":
        await message.answer("❌ У вас нет права управлять участниками.")
        return False
    return True


async def _bot_can_restrict(message: types.Message) -> bool:
    try:
        me = await message.bot.get_me()
        member = await message.bot.get_chat_member(message.chat.id, me.id)
    except Exception:
        return False
    return getattr(member, "status", "") == "creator" or bool(getattr(member, "can_restrict_members", False))


async def _resolve_target(message: types.Message, args: list[str]):
    reply = message.reply_to_message
    if reply and reply.from_user and not reply.from_user.is_bot:
        u = reply.from_user
        await bot_touch_user(
            u.id,
            u.username or "",
            u.first_name or "",
            u.last_name or "",
            u.full_name,
            "GROUP",
        )
        return {
            "tg_id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "minecraft_nick": None,
        }, args

    if not args:
        return None, args

    target = args[0]
    result = await bot_find_user(target)
    if result.error or not isinstance(result.data, dict) or result.data.get("error"):
        return None, args

    target = dict(result.data)
    if "username" not in target and "telegram_username" in target:
        target["username"] = target.get("telegram_username")
    if "minecraft_nick" not in target and "minecraft_nickname" in target:
        target["minecraft_nick"] = target.get("minecraft_nickname")
    return target, args[1:]


def _name(target: dict) -> str:
    return escape(
        str(
            target.get("minecraft_nick")
            or target.get("username")
            or target.get("full_name")
            or target.get("tg_id")
            or "пользователь"
        )
    )


def _reason(args: list[str], multiline: str, default: str = "Не указано") -> str:
    inline = " ".join(args).strip()
    return (multiline or inline or default).strip()[:2000]


async def _punish(message: types.Message, kind: str):
    needs_restrict = kind in {"warn", "mute", "ban", "kick"}
    if not await _chat_admin(message, need_restrict=needs_restrict):
        return

    args, multiline = _first_line(message.text or "")
    if kind == "kick" and args and args[0].casefold() == "неактив":
        return await _kick_inactive(message, args[1:])

    if kind in {"mute", "ban"}:
        duration, args = _duration_from_args(args)
    else:
        duration = None

    target, rest = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя командой или ответом на его сообщение.")
        return

    if kind in {"mute", "ban"} and duration is None:
        parsed_duration, rest_after_duration = _duration_from_args(rest)
        if parsed_duration is not None:
            duration = parsed_duration
            rest = rest_after_duration

    if kind == "mute" and duration is None:
        duration = 7200

    reason = _reason(rest, multiline, "Нарушение правил" if kind != "kick" else "Кик")

    if target.get("tg_id") == message.from_user.id:
        await message.answer("❌ Нельзя применить это действие к себе.")
        return

    if needs_restrict and not await _bot_can_restrict(message):
        await message.answer("❌ У Prisma нет права управлять участниками в этом чате.")
        return

    if duration is not None:
        # Telegram treats very short temporary restrictions inconsistently.
        # Normalize all timed chat sanctions to at least one minute.
        duration = max(60, duration)
    minutes = None if duration is None else (duration + 59) // 60
    if minutes is not None:
        duration = minutes * 60

    created = await bot_create_chat_punishment(
        message.chat.id,
        int(target["tg_id"]),
        kind,
        reason,
        message.from_user.id,
        minutes,
    )
    if created.error or not isinstance(created.data, dict) or not created.data.get("success"):
        error = safe_rpc_error(created)
        messages = {
            "ADMIN_LACKS_PERMISSION": "❌ У вас нет права на эту команду в PRISMA.",
            "STAFF_HIERARCHY_FORBIDS": "❌ Нельзя наказать администратора равного или более высокого уровня.",
            "SELF_PUNISHMENT_FORBIDDEN": "❌ Нельзя наказать себя.",
            "INVALID_REASON": "❌ Укажите причину.",
            "USER_NOT_FOUND": "❌ Пользователь не найден в базе PRISMA.",
        }
        await message.answer(messages.get(error, "❌ Не удалось сохранить наказание."))
        return

    tg_id = int(target["tg_id"])
    until = None if duration is None else datetime.now(timezone.utc) + timedelta(seconds=duration)
    if kind == "mute":
        if bool(created.data.get("chat_has_indefinite_mute")):
            until = None
        else:
            effective_expiry = created.data.get("chat_muted_until")
            if effective_expiry:
                try:
                    parsed_expiry = datetime.fromisoformat(str(effective_expiry).replace("Z", "+00:00"))
                    until = parsed_expiry if parsed_expiry.tzinfo else parsed_expiry.replace(tzinfo=timezone.utc)
                except (TypeError, ValueError, OverflowError):
                    await message.answer("⚠️ Мут записан, но не удалось определить общий срок ограничения. Проверьте наказания игрока.")
                    return
    try:
        if kind == "mute":
            await message.bot.restrict_chat_member(
                message.chat.id,
                tg_id,
                permissions=muted_chat_permissions(),
                use_independent_chat_permissions=True,
                until_date=until,
            )
        elif kind == "ban":
            await message.bot.ban_chat_member(message.chat.id, tg_id, until_date=until, revoke_messages=False)
        elif kind == "kick":
            await message.bot.ban_chat_member(message.chat.id, tg_id, revoke_messages=False)
            await message.bot.unban_chat_member(message.chat.id, tg_id, only_if_banned=True)
        elif kind == "warn" and bool(created.data.get("auto_banned")):
            await message.bot.ban_chat_member(message.chat.id, tg_id, revoke_messages=False)
    except Exception:
        # Keep the database/audit state consistent when Telegram rejected the action.
        punishment_id = (created.data or {}).get("punishment_id") if isinstance(created.data, dict) else None
        if punishment_id:
            await bot_revoke_chat_punishment(punishment_id, message.from_user.id)
        await message.answer("❌ Telegram не дал применить наказание. Запись PRISMA откатили.")
        return

    labels = {"warn": "⚠️ Варн", "mute": "🔇 Мут", "ban": "⛔ Бан", "kick": "👢 Кик"}
    if kind == "warn" and bool(created.data.get("auto_banned")):
        suffix = " · 5 активных варнов → бан"
    else:
        suffix = "" if duration is None else f" на {escape(_duration_label(duration))}"
    await message.answer(
        f"{labels[kind]}: <b>{_name(target)}</b>{suffix}\nПричина: {escape(reason)}",
        parse_mode="HTML",
    )


def _duration_label(seconds: int) -> str:
    if seconds % 604800 == 0:
        return f"{seconds // 604800} нед."
    if seconds % 86400 == 0:
        return f"{seconds // 86400} дн."
    if seconds % 3600 == 0:
        return f"{seconds // 3600} ч."
    if seconds % 60 == 0:
        return f"{seconds // 60} мин."
    return f"{seconds} сек."


async def _lift(message: types.Message, kind: str):
    if not await _chat_admin(message, need_restrict=True):
        return
    args, _ = _first_line(message.text or "")
    target, rest = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return

    tg_id = int(target["tg_id"])

    if kind == "mute":
        # Update the database first. It returns whether another active mute still
        # applies to this group, plus the effective expiry across overlapping mutes.
        result = await bot_lift_chat_punishment(
            message.chat.id,
            tg_id,
            "MUTE",
            message.from_user.id,
        )
        if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
            await message.answer("❌ Не удалось снять мут в PRISMA.")
            return

        data = result.data
        still_muted = bool(data.get("chat_is_muted"))
        try:
            if still_muted:
                if bool(data.get("chat_has_indefinite_mute")):
                    until = None
                else:
                    raw_expiry = data.get("chat_muted_until")
                    if not raw_expiry:
                        raise ValueError("missing effective mute expiry")
                    until = datetime.fromisoformat(str(raw_expiry).replace("Z", "+00:00"))
                    if until.tzinfo is None:
                        until = until.replace(tzinfo=timezone.utc)

                await message.bot.restrict_chat_member(
                    message.chat.id,
                    tg_id,
                    permissions=muted_chat_permissions(),
                    use_independent_chat_permissions=True,
                    until_date=until,
                )
            else:
                await message.bot.restrict_chat_member(
                    message.chat.id,
                    tg_id,
                    permissions=unmuted_chat_permissions(),
                    use_independent_chat_permissions=True,
                )
        except Exception:
            await message.answer(
                "⚠️ Запись наказания обновлена в PRISMA, но не удалось синхронизировать ограничение Telegram. "
                "Проверьте права бота в группе."
            )
            return

        if not still_muted:
            try:
                display_name = str(target.get("full_name") or target.get("username") or tg_id)
                await ensure_onboarding_restriction(message.bot, tg_id, display_name)
            except Exception:
                # The periodic membership worker will retry the onboarding restriction.
                pass
            await message.answer(f"✅ Мут снят с <b>{_name(target)}</b>.", parse_mode="HTML")
        else:
            if bool(data.get("chat_has_indefinite_mute")):
                expiry_label = "без срока окончания"
            else:
                expiry_label = str(data.get("chat_muted_until") or "срок не определён")
            await message.answer(
                f"ℹ️ Один мут снят с <b>{_name(target)}</b>, но другое активное ограничение ещё действует: {escape(expiry_label)}.",
                parse_mode="HTML",
            )
        return

    # Ban handling remains independent from mute reconciliation.
    try:
        await message.bot.unban_chat_member(
            message.chat.id,
            tg_id,
            only_if_banned=True,
        )
    except Exception:
        await message.answer("❌ Не удалось снять бан в Telegram.")
        return

    result = await bot_lift_chat_punishment(
        message.chat.id,
        tg_id,
        "BAN",
        message.from_user.id,
    )
    if result.error:
        await message.answer("⚠️ Бан снят в Telegram, но запись PRISMA не обновилась.")
        return

    await message.answer(f"✅ Ограничение снято с <b>{_name(target)}</b>.", parse_mode="HTML")


async def _kick_inactive(message: types.Message, args: list[str]):
    if not await _chat_admin(message, need_restrict=True):
        return
    days = 30
    if args:
        duration, _ = _duration_from_args(args)
        if duration is None:
            try:
                days = max(1, int(args[0]))
            except ValueError:
                await message.answer("❌ Пример: /кик неактив 30д или /кик неактив 30")
                return
        else:
            days = max(1, duration // 86400)

    rows = await bot_list_inactive_members(days, 100)
    if rows.error or not isinstance(rows.data, list):
        await message.answer("❌ Не удалось получить список неактивных.")
        return

    admin_ids = set()
    try:
        for member in await message.bot.get_chat_administrators():
            admin_ids.add(member.user.id)
    except Exception:
        pass

    kicked = 0
    skipped = 0
    for row in rows.data:
        tg_id = int(row.get("tg_id"))
        if tg_id == message.from_user.id or tg_id in admin_ids:
            skipped += 1
            continue
        try:
            await message.bot.ban_chat_member(message.chat.id, tg_id, revoke_messages=False)
            await message.bot.unban_chat_member(message.chat.id, tg_id, only_if_banned=True)
            kicked += 1
        except Exception:
            skipped += 1

    await message.answer(
        f"👢 Кик неактивных завершён.\nУдалено: <b>{kicked}</b>\nПропущено: <b>{skipped}</b>",
        parse_mode="HTML",
    )


@router.message(Command(*MODERATION_ALIASES["warn"], ignore_case=True))
async def warn_command(message: types.Message):
    if _is_prisma_chat(message):
        await _punish(message, "warn")


@router.message(Command(*MODERATION_ALIASES["mute"], ignore_case=True))
async def mute_command(message: types.Message):
    if _is_prisma_chat(message):
        await _punish(message, "mute")


@router.message(Command(*MODERATION_ALIASES["ban"], ignore_case=True))
async def ban_command(message: types.Message):
    if _is_prisma_chat(message):
        await _punish(message, "ban")


@router.message(Command(*MODERATION_ALIASES["kick"], ignore_case=True))
async def kick_command(message: types.Message):
    if _is_prisma_chat(message):
        await _punish(message, "kick")


@router.message(Command(*MODERATION_ALIASES["unmute"], ignore_case=True))
async def unmute_command(message: types.Message):
    if _is_prisma_chat(message):
        await _lift(message, "mute")


@router.message(Command(*MODERATION_ALIASES["unban"], ignore_case=True))
async def unban_command(message: types.Message):
    if _is_prisma_chat(message):
        await _lift(message, "ban")


@router.message(Command(*MODERATION_ALIASES["unwarn"], ignore_case=True))
async def unwarn_command(message: types.Message):
    if not _is_prisma_chat(message) or not await _chat_admin(message):
        return
    args, _ = _first_line(message.text or "")
    target, _ = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return
    result = await bot_lift_chat_punishment(
        message.chat.id,
        int(target["tg_id"]),
        "WARN",
        message.from_user.id,
    )
    if result.error:
        await message.answer("❌ Не удалось снять варн.")
        return
    await message.answer(f"✅ Последний варн снят с <b>{_name(target)}</b>.", parse_mode="HTML")


@router.message(Command("варны", "warns"))
async def warns_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    target, _ = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return
    result = await bot_get_chat_warnings(message.chat.id, int(target["tg_id"]))
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить варны.")
        return
    if not result.data:
        await message.answer(f"✅ У <b>{_name(target)}</b> нет активных варнов.", parse_mode="HTML")
        return
    lines = [f"⚠️ <b>Варны {_name(target)}</b>"]
    for index, row in enumerate(result.data, 1):
        lines.append(
            f"{index}. {escape(str(row.get('reason') or 'Не указано'))} · "
            f"<code>{escape(str(row.get('created_at') or ''))}</code>"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("муты", "mutes"))
async def mutes_command(message: types.Message):
    if not _is_prisma_chat(message) or not await _chat_admin(message):
        return
    result = await bot_get_chat_mutes(message.chat.id)
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список мутов.")
        return
    if not result.data:
        await message.answer("🔇 Активных мутов нет.")
        return
    lines = ["🔇 <b>Активные муты</b>"]
    for row in result.data[:30]:
        lines.append(
            f"• {escape(str(row.get('full_name') or row.get('username') or row.get('tg_id')))} — "
            f"{escape(str(row.get('reason') or 'Не указано'))}"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")




def _parse_timestamp(value):
    if not value:
        return None
    try:
        raw = str(value).replace("Z", "+00:00")
        dt = datetime.fromisoformat(raw)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def _elapsed_label(value) -> str:
    dt = value if isinstance(value, datetime) else _parse_timestamp(value)
    if not dt:
        return "—"
    now = datetime.now(timezone.utc)
    seconds = max(0, int((now - dt).total_seconds()))
    if seconds < 60:
        return "меньше минуты"
    minutes = seconds // 60
    hours = minutes // 60
    days = hours // 24
    if days >= 30:
        months = days // 30
        rest_days = days % 30
        if rest_days:
            return f"{months} мес. {rest_days} дн."
        return f"{months} мес."
    if days:
        rest_hours = hours % 24
        return f"{days} дн. {rest_hours} ч." if rest_hours else f"{days} дн."
    return f"{hours} ч. {minutes % 60} мин." if hours else f"{minutes} мин."


def _relative_label(value) -> str:
    dt = value if isinstance(value, datetime) else _parse_timestamp(value)
    if not dt:
        return "—"
    elapsed = _elapsed_label(dt)
    if elapsed == "меньше минуты":
        return "только что"
    return f"{elapsed} назад"


def _compact_number(value) -> str:
    try:
        number = int(value or 0)
    except (TypeError, ValueError):
        number = 0
    if number < 1000:
        return str(number)
    formatted = f"{number / 1000:.1f}".rstrip("0").rstrip(".").replace(".", ",")
    return f"{formatted}k"


def _mention(tg_id, full_name=None, username=None) -> str:
    label = escape(str(full_name or username or tg_id or "пользователь"))
    if username:
        href = f"https://t.me/{escape(str(username).lstrip('@'), quote=True)}"
    elif tg_id:
        href = f"tg://openmessage?user_id={int(tg_id)}"
    else:
        return label
    return f'<a href="{href}">{label}</a>'


def _staff_role_label(role: str) -> str:
    return {
        "helper": "Хелпер",
        "moderator": "Модератор",
        "admin": "Админ",
        "head_admin": "Старший админ",
        "owner": "Владелец",
    }.get(str(role or "").casefold(), str(role or "Staff"))


async def _send_chat_profile(message: types.Message, target: dict, title: str):
    tg_id = int(target["tg_id"])
    profile_result = await bot_get_profile(tg_id)
    data = dict(profile_result.data) if (
        not profile_result.error
        and isinstance(profile_result.data, dict)
        and not profile_result.data.get("error")
    ) else dict(target)

    clan_name = "—"
    clan_result = await bot_get_clan_info(tg_id)
    if (
        not clan_result.error
        and isinstance(clan_result.data, dict)
        and not clan_result.data.get("error")
    ):
        clan_name = str(clan_result.data.get("name") or "—")

    staff_row = None
    staff_result = await bot_list_staff()
    if not staff_result.error and isinstance(staff_result.data, list):
        staff_row = next(
            (row for row in staff_result.data if int(row.get("tg_id") or 0) == tg_id),
            None,
        )

    chat_admin = False
    try:
        member = await message.bot.get_chat_member(message.chat.id, tg_id)
        chat_admin = getattr(member, "status", "") in {"administrator", "creator"}
    except Exception:
        pass

    status = "—"
    if data.get("is_banned"):
        status = "бан"
    elif data.get("is_muted"):
        status = "мут"

    username = str(data.get("username") or target.get("username") or "").lstrip("@")
    minecraft = str(data.get("minecraft_nick") or target.get("minecraft_nick") or "—")
    lines = [
        f"👤 <b>{escape(title)}</b>",
        "",
        f"Имя: {_mention(tg_id, data.get('full_name') or target.get('full_name'), username or None)}",
    ]
    if username:
        lines.append(f"Username: <b>@{escape(username)}</b>")
    lines.append(f"Minecraft: <code>{escape(minecraft)}</code>")
    lines.append(f"Whitelist: {'✅' if data.get('is_whitelisted') else '❌'}")

    # Extras appear only when there is something worth saying.
    warns = int(data.get("active_warns") or 0)
    if warns:
        lines.append(f"⚠️ Активных варнов: <b>{warns}</b>")
    if clan_name != "—":
        lines.append(f"⚔️ Клан: <b>{escape(clan_name)}</b>")
    if staff_row:
        rank = int(staff_row.get("rank") or 0)
        role = _staff_role_label(staff_row.get("role"))
        lines.append(f"⭐ [{rank}] Ранг: <b>{escape(role)}</b>")
    elif chat_admin:
        lines.append("👨🏻‍🔧 Телеграм-админ этого чата")
    if status != "—":
        lines.append(f"🚫 Статус: <b>{escape(status)}</b>")

    await message.answer("\n".join(lines), parse_mode="HTML")


async def _handle_who(message: types.Message):
    args, _ = _first_line(message.text or "")
    first = args[0].casefold() if args else ""

    if first in {"админ", "админы", "модер", "модеры", "staff"}:
        result = await bot_list_staff()
        if result.error or not isinstance(result.data, list):
            await message.answer("❌ Не удалось получить состав PRISMA staff.")
            return
        if not result.data:
            await message.answer("🛡 В PRISMA staff пока никого нет.")
            return
        lines = ["🛡 <b>PRISMA STAFF</b>"]
        for row in result.data:
            name = _mention(row.get("tg_id"), row.get("full_name"), row.get("telegram_username"))
            role = escape(str(row.get("role") or "staff"))
            rank_label = escape(str(row.get("rank_label") or row.get("rank") or "—"))
            lines.append(f"• {name} — {role} · уровень <b>{rank_label}</b>")
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if first in {"неактив", "неактивные"}:
        days = _inactive_days(args[1:], 7)
        result = await bot_list_inactive_members(days, 100)
        if result.error or not isinstance(result.data, list):
            await message.answer("❌ Не удалось получить список неактивных.")
            return
        if not result.data:
            await message.answer(f"✅ За {_days_label(days)} неактивных не найдено.")
            return
        lines = [f"✖️ <b>Неактив чата: больше, ніж {_days_label(days)}:</b>"]
        for index, row in enumerate(result.data[:50], 1):
            name = row.get("display_name") or row.get("username") or row.get("telegram_id")
            mention = _mention(row.get("telegram_id"), name, row.get("username"))
            message_link = row.get("message_link")
            suffix = f'<a href="{escape(str(message_link), quote=True)}">⁬</a>' if message_link else "⁬"
            age = _elapsed_label(_parse_timestamp(row.get("last_seen_at"))) if row.get("last_seen_at") else "нет активности"
            lines.append(f"{index}. {mention}{suffix} ({age})")
        lines.append(f"🗓 <b>Всего неактивных: {len(result.data)}</b>")
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if first in {"я", "я?", "me"} and len(args) == 1:
        target = {
            "tg_id": message.from_user.id,
            "username": message.from_user.username,
            "full_name": message.from_user.full_name,
            "minecraft_nick": None,
        }
        await _send_chat_profile(message, target, "Кто я")
        return

    if first in {"ты", "ты?"}:
        target = None
        if len(args) > 1:
            target, _ = await _resolve_target(message, args[1:])
        elif message.reply_to_message and message.reply_to_message.from_user:
            u = message.reply_to_message.from_user
            target = {
                "tg_id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "minecraft_nick": None,
            }
        if not target:
            await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
            return
        await _send_chat_profile(message, target, "Кто ты")
        return

    if not args and message.reply_to_message and message.reply_to_message.from_user:
        u = message.reply_to_message.from_user
        target = {
            "tg_id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "minecraft_nick": None,
        }
        await _send_chat_profile(message, target, "Кто ты")
        return

    target, _ = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Используйте /кто я, /кто ты @username или ответом на сообщение.")
        return
    await _send_chat_profile(message, target, "Кто ты")


@router.message(Command("кто", "who"))
async def who_command(message: types.Message):
    if _is_prisma_chat(message):
        await _handle_who(message)


@router.message(F.text.regexp(r"(?i)^кто\s+(?:я\??|ты(?:\s+.+)?|админ(?:ы)?|неактив(?:\s+\d+)?)$"))
async def plain_who_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    clone = message.model_copy(update={"text": "/" + (message.text or "").strip()})
    await who_command(clone)


@router.message(Command("help"))
async def group_help_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    await message.answer(
        "🤖 <b>PRISMA — команды чата</b>\n"
        "━━━━━━━━━━━━━━━━\n"
        "<b>👤 ПРОФИЛИ</b>\n"
        "<code>кто я</code> или <code>/кто я</code> — информация о себе.\n"
        "<code>кто ты @username</code> — информация о пользователе.\n"
        "<code>/кто админ</code> — состав PRISMA staff.\n"
        "<code>/неактив</code> — кто молчит больше недели (<code>/неактив месяц</code>, <code>/неактив 14</code>).\n\n"
        "<b>🏆 АКТИВНОСТЬ</b>\n"
        "<code>топ</code> или <code>/топ</code> — топ сообщений за неделю.\n"
        "<code>/топ сутки</code> — топ за сутки.\n"
        "<code>/топ месяц 20</code> — топ за месяц.\n"
        "<code>топ 20 вся</code> — топ за всё время.\n"
        "<code>стата</code> / <code>/стата</code> — общая статистика чата.\n"
        "<code>актив</code> / <code>/кто_онлайн</code> — кто активен сейчас.\n\n"
        "<b>⚔️ КЛАНЫ</b>\n"
        "<code>кланы</code> — список кланов.\n"
        "<code>/мойклан</code> — мой клан. <code>клан 1</code> — подробности.\n"
        "<code>/клан создать Название</code> — создать клан.\n"
        "<code>/клан вступить Название</code> — вступить.\n"
        "<code>/клан выйти</code> — выйти из клана.\n"
        "<code>/отн @ник</code> — запрос на отношения; <code>/отн</code> — статус и заявки.\n"
        "<code>/брак @ник</code> — предложение; <code>/брак</code> — статус и предложения.\n<code>браки</code> — список активных браков.\n\n"
        "<b>🎲 УТИЛИТЫ</b>\n"
        "<code>/рандом 1 100</code> — случайное число.\n"
        "<code>/данет</code> — да или нет.\n"
        "<code>/выбери левое или правое</code> — выбор.\n"
        "<code>/инфа вопрос</code> — случайный шанс.\n"
        "<code>/жребий</code> — жеребьёвка.\n"
        "<code>/скажи текст</code> — повторить текст.\n\n"
        "<b>💬 ЧАТ</b>\n"
        "<code>-чат</code> — закрыть чат.\n"
        "<code>+чат</code> — открыть чат.\n\n"
        "<b>🛡 МОДЕРАЦИЯ</b>\n"
        "<code>/варн</code> / <code>/мут</code> / <code>/бан</code> / <code>/кик</code>\n"
        "<code>/размут</code> / <code>/разбан</code> / <code>/снятьварн</code>\n"
        "<code>/варны</code> / <code>/муты</code> — списки наказаний.\n"
        "Ответом на сообщение команды работают без username.",
        parse_mode="HTML",
    )




@router.message(Command("топ", "top"))
async def top_group_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    period_tokens = {"сутки": 1, "день": 1, "неделя": 7, "месяц": 30, "вся": None, "всё": None, "все": None}
    days = None
    mode = "вся"
    for token in args:
        normalized = token.casefold()
        if normalized in period_tokens:
            mode = normalized
            days = period_tokens[normalized]
            break
    if not any(token.casefold() in period_tokens for token in args):
        days = 7
        mode = "неделя"
    limit = 10
    for token in args:
        if token.isdigit():
            limit = min(100, max(1, int(token)))
            break
    result = await bot_chat_top(message.chat.id, days, limit)
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить статистику.")
        return
    total_result = await bot_chat_top_total(message.chat.id, days)
    total = int(total_result.data or 0) if not total_result.error else sum(int(row.get("messages") or 0) for row in result.data)
    title = "всё время" if days is None else f"за {mode}"
    lines = [f"🏆 <b>Топ {title}</b>"]
    if not result.data:
        lines.append("Пока нет статистики сообщений.")
    else:
        for i, row in enumerate(result.data, 1):
            display_name = row.get("source_display_name") or row.get("full_name") or row.get("telegram_username") or row.get("tg_id")
            username = row.get("source_username") if row.get("source_display_name") else row.get("telegram_username")
            tg_id = row.get("source_tg_id") or row.get("tg_id")
            if days is None:
                display_name = row.get("minecraft_nickname") or display_name
            mention = _mention(tg_id, display_name, username)
            lines.append(f"{i}. {mention} — {row.get('messages', 0)}")
    lines.append(f"\nВсего сообщений: <b>{total:,}</b>".replace(",", " "))
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("ники", "nicks", "nicknames"))
async def nicknames_group_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_list_current_participants()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список участников.")
        return
    if not result.data:
        await message.answer("ℹ️ Зарегистрированных участников пока нет.")
        return

    lines = ["👥 <b>Участники PRISMA:</b>"]
    for index, row in enumerate(result.data, 1):
        name = row.get("display_name") or row.get("username") or row.get("telegram_id") or "участник"
        mention = _mention(row.get("telegram_id"), name, row.get("username"))
        nickname = escape(str(row.get("nickname") or "—"))
        lines.append(f"{index}. {mention} — <code>{nickname}</code>")
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(F.text.regexp(r"(?i)^ники$"))
async def plain_nicknames_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    clone = message.model_copy(update={"text": "/ники"})
    await nicknames_group_command(clone)


@router.message(Command("стата", "stats"))
async def stats_group_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_chat_stats(message.chat.id)
    if result.error or not isinstance(result.data, dict):
        await message.answer("❌ Не удалось получить статистику чата.")
        return
    total = int(result.data.get("total_messages") or 0)
    current = int(result.data.get("current_messages") or 0)
    users = int(result.data.get("unique_users") or 0)
    await message.answer(
        "📊 <b>Статистика PRISMA</b>\n"
        f"Всего сообщений: <b>{total:,}</b>\n"
        f"Сообщений сегодня: <b>{current:,}</b>\n"
        f"Участников в статистике: <b>{users}</b>",
        parse_mode="HTML",
    )


@router.message(F.text.regexp(r"(?i)^стат(?:а|истика)$"))
async def plain_stats_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    clone = message.model_copy(update={"text": "/стата"})
    await stats_group_command(clone)


@router.message(F.text.regexp(r"(?i)^топ(?:\s+.+)?$"))
async def plain_top_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    raw = (message.text or "").strip()
    clone = message.model_copy(update={"text": "/" + raw})
    await top_group_command(clone)


@router.message(Command("неактив", "кто_неактив", "inactive"))
async def inactive_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    days = _inactive_days(args, 7)
    result = await bot_list_inactive_members(days, 100)
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список неактивных.")
        return
    if not result.data:
        await message.answer(f"✅ За {_days_label(days)} неактивных не найдено.")
        return
    lines = [f"✖️ <b>Неактив чата: больше, чем {_days_label(days)}:</b>"]
    for index, row in enumerate(result.data[:50], 1):
        name = row.get("display_name") or row.get("username") or row.get("telegram_id")
        mention = _mention(row.get("telegram_id"), name, row.get("username"))
        message_link = row.get("message_link")
        suffix = f'<a href="{escape(str(message_link), quote=True)}">⁬</a>' if message_link else "⁬"
        age = _elapsed_label(_parse_timestamp(row.get("last_seen_at"))) if row.get("last_seen_at") else "нет активности"
        lines.append(f"{index}. {mention}{suffix} ({age})")
    lines.append(f"🗓 <b>Всего неактивных: {len(result.data)}</b>")
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("бот", "призма", "ping"))
async def bot_info_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    await message.answer("✅ На месте\n🤖 <b>PRISMA</b> на месте.\nКоманды: /help", parse_mode="HTML")


@router.message(Command("рандом", "random"))
async def random_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    if not args or not all(re.fullmatch(r"-?\d+", x) for x in args[:2]):
        await message.answer("❌ Пример: /рандом 1 100")
        return
    a = int(args[0])
    b = int(args[1]) if len(args) > 1 else a
    if a > b:
        a, b = b, a
    await message.answer(f"🎲 Выпало: <b>{random.randint(a, b)}</b>", parse_mode="HTML")


@router.message(Command("данет"))
async def yes_no_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    answers = ("да", "нет", "не знаю", "скорее да", "скорее нет")
    await message.answer(f"🔮 Ответ: <b>{random.choice(answers)}</b>", parse_mode="HTML")


@router.message(Command("обнять", "пожать", "датьпять", "поддержать"))
async def rp_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    target, _ = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return
    command = (message.text or "").split(maxsplit=1)[0].lstrip("/").casefold()
    if command == "обнять":
        action = "обнял(а)"
    elif command == "пожать":
        action = "пожал(а) руку"
    elif command == "датьпять":
        action = "дал(а) пять"
    else:
        action = "поддержал(а)"
    await message.answer(
        f"🤝 <b>{escape(message.from_user.full_name)}</b> {action} <b>{_name(target)}</b>."
    , parse_mode="HTML")


@router.message(Command("кланы", "clans"))
async def clans_list_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_list_clans()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список кланов.")
        return
    if not result.data:
        await message.answer("⚔️ Кланов пока нет.")
        return
    lines = ["⚔️ <b>Кланы PRISMA</b>"]
    for i, clan in enumerate(result.data[:30], 1):
        name = escape(str(clan.get("name") or "Без названия"))
        tag = escape(str(clan.get("tag") or ""))
        leader = _mention(
            clan.get("owner_tg_id"),
            clan.get("owner_full_name"),
            clan.get("owner_username"),
        )
        member_count = int(clan.get("member_count") or 0)
        tag_part = f" <code>[{tag}]</code>" if tag else ""
        lines.append(
            f"{i}. <b>{name}</b>{tag_part} · {member_count} участн.\n"
            f"   Лидер: {leader}"
        )
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(F.text.regexp(r"(?i)^кланы$"))
async def plain_clans_list_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    clone = message.model_copy(update={"text": "/кланы"})
    await clans_list_command(clone)


@router.message(Command("мойклан", "мой_клан"))
async def my_clan_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_get_clan_info(message.from_user.id)
    if result.error:
        await message.answer("❌ Не удалось получить клан.")
        return
    if isinstance(result.data, dict) and result.data.get("error") == "NO_CLAN":
        await message.answer("⚔️ Вы не состоите в клане. /клан вступить <название>")
        return
    data = result.data if isinstance(result.data, dict) else {}
    members = data.get("members") or []
    lines = [
        f"⚔️ <b>Клан {escape(str(data.get('name') or '—'))}</b> <code>[{escape(str(data.get('tag') or ''))}]</code>",
        f"Уровень: <b>{data.get('level', 1)}</b> · XP: <b>{data.get('xp', 0)}</b>",
        f"Рейтинг: <b>{data.get('rating', 0)}</b>",
        f"Участников: <b>{len(members)}</b>",
    ]
    for member in members[:20]:
        lines.append(f"• {escape(str(member.get('full_name') or member.get('minecraft_nick') or member.get('tg_id') or 'Игрок'))}")
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("клан", "clan"))
async def clan_group_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, multiline = _first_line(message.text or "")
    sub = args[0].casefold() if args else ""

    if sub.isdigit():
        position = int(sub)
        if not 1 <= position <= 100:
            await message.answer("❌ Номер клана должен быть от 1 до 100.")
            return
        result = await bot_get_clan_by_position(position)
        if result.error or not isinstance(result.data, dict) or result.data.get("error"):
            await message.answer("❌ Клан с таким номером не найден.")
            return

        data = result.data
        leader = data.get("leader") or {}
        leader_link = _mention(leader.get("tg_id"), leader.get("full_name"), leader.get("username"))
        clan_type = {
            "open": "Открытый",
            "closed": "Закрытый",
            "private": "Закрытый",
        }.get(str(data.get("type") or "").casefold(), str(data.get("type") or "—"))
        created = _parse_timestamp(data.get("created_at"))
        members = data.get("members") or []

        lines = [
            f"⚔️ <b>[{position}] Клан «{escape(str(data.get('name') or '—'))}»</b>",
            f"🔆 Лидер: {leader_link}",
            f"🗓 Основан: {created.strftime('%d.%m.%Y') if created else '—'}" + (f" ({_elapsed_label(created)} назад)" if created else ""),
            f"✅ Тип: {escape(clan_type)}",
            f"☢️ Репутация: <b>{data.get('rating', 0)}</b>",
            f"📊 Уровень: <b>{data.get('level', 1)}</b> · XP: <b>{data.get('xp', 0)}</b>",
            f"💰 Баланс: <b>{data.get('balance', 0)}</b>",
            f"🏆 Победы/поражения: <b>{data.get('wins', 0)}/{data.get('losses', 0)}</b>",
            f"👥 Участников: <b>{len(members)}</b>",
        ]
        if data.get("description"):
            lines.append(f"📝 {escape(str(data.get('description')))}")
        if members:
            lines.append("")
            lines.append(f"⚔️ <b>Участники клана «{escape(str(data.get('name') or '—'))}»</b>")
            for index, member in enumerate(members[:50], 1):
                joined = _parse_timestamp(member.get("joined_at"))
                age = f" ({_elapsed_label(joined)})" if joined else ""
                role = " · владелец" if str(member.get("role") or "").casefold() == "owner" else ""
                lines.append(
                    f"{index}. {_mention(member.get('tg_id'), member.get('full_name'), member.get('username'))}{role}{age}"
                )
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if sub in {"создать", "create"}:
        name = " ".join(args[1:]).strip() or multiline.strip()
        if not name:
            await message.answer("❌ Пример: /клан создать Название")
            return
        result = await bot_create_clan(message.from_user.id, name)
        if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
            error = str(result.error or (result.data or {}).get("error") or result.data)
            messages = {
                "USER_ALREADY_IN_CLAN": "❌ Вы уже состоите в клане.",
                "CLAN_NAME_TAKEN": "❌ Такое название клана уже занято.",
                "USER_NOT_ALLOWED": "⏳ Создавать кланы можно после одобрения заявки.",
            }
            await message.answer(messages.get(error, "❌ Не удалось создать клан."), parse_mode="HTML")
            return
        await message.answer(
            f"✅ Клан <b>{escape(name)}</b> создан. Тег: <code>[{escape(str(result.data.get('tag') or ''))}]</code>",
            parse_mode="HTML",
        )
        return

    if sub in {"войны", "война", "wars", "war"}:
        action = args[1].casefold() if len(args) >= 2 else ""

        if action in {"создать", "create"} and len(args) >= 3:
            target = " ".join(args[2:]).strip()
            result = await bot_create_clan_war(message.from_user.id, target)
            if result.error:
                messages = {
                    "NO_CLAN_PERMISSION": "❌ Объявить войну может только владелец или офицер клана.",
                    "CLAN_NOT_FOUND": "❌ Клан не найден.",
                    "WAR_ALREADY_ACTIVE": "❌ У вашего клана уже есть незавершённая война.",
                }
                await message.answer(messages.get(str(result.error), "❌ Не удалось объявить войну."))
                return
            await message.answer(
                f"⚔️ Вызов клану <b>[{escape(str(result.data.get('target_tag') or '—'))}] "
                f"{escape(str(result.data.get('target_clan') or 'Клан'))}</b> отправлен.",
                parse_mode="HTML",
            )
            return

        if action in {"принять", "accept"} and len(args) >= 3:
            result = await bot_respond_clan_war(message.from_user.id, args[2].strip(), "ACCEPT")
            if result.error:
                messages = {
                    "WAR_NOT_PENDING": "❌ Этот вызов уже обработан.",
                    "NO_CLAN_PERMISSION": "❌ Только владелец или офицер целевого клана может принять вызов.",
                }
                await message.answer(messages.get(str(result.error), "❌ Не удалось принять вызов."))
                return
            await message.answer("✅ Вызов принят. Войну можно начать.")
            return

        if action in {"отклонить", "отказать", "deny"} and len(args) >= 3:
            result = await bot_respond_clan_war(message.from_user.id, args[2].strip(), "DECLINE")
            if result.error:
                await message.answer("❌ Не удалось отклонить вызов.")
                return
            await message.answer("✅ Вызов отклонён.")
            return

        if action in {"начать", "start"} and len(args) >= 3:
            result = await bot_start_clan_war(message.from_user.id, args[2].strip())
            if result.error:
                messages = {
                    "WAR_NOT_SCHEDULED": "❌ Сначала вызов должен быть принят.",
                    "NO_CLAN_PERMISSION": "❌ Начать войну может только владелец или офицер клана.",
                }
                await message.answer(messages.get(str(result.error), "❌ Не удалось начать войну."))
                return
            await message.answer("⚔️ Война началась.")
            return

        if action in {"завершить", "finish"} and len(args) >= 5:
            try:
                score_a = int(args[3])
                score_b = int(args[4])
            except ValueError:
                await message.answer("❌ Счёт должен быть целым числом.")
                return
            result = await bot_finish_clan_war(
                message.from_user.id, args[2].strip(), score_a, score_b
            )
            if result.error:
                messages = {
                    "INVALID_SCORE": "❌ Счёт не может быть отрицательным.",
                    "WAR_NOT_ACTIVE": "❌ Активной войны с таким ID нет.",
                    "NO_CLAN_PERMISSION": "❌ Завершить войну может только владелец или офицер клана.",
                }
                await message.answer(messages.get(str(result.error), "❌ Не удалось завершить войну."))
                return
            await message.answer(
                f"✅ Война завершена со счётом <b>{score_a}:{score_b}</b>. Рейтинг кланов обновлён.",
                parse_mode="HTML",
            )
            return

        result = await bot_list_clan_wars(message.from_user.id)
        if result.error or not isinstance(result.data, dict):
            await message.answer("❌ Не удалось получить список войн.")
            return
        wars = result.data.get("wars") or []
        if not wars:
            await message.answer(
                "ℹ️ У вашего клана пока нет войн.\n"
                "Создать вызов: /клан война создать НАЗВАНИЕ_ИЛИ_ТЕГ"
            )
            return

        status_labels = {
            "pending": "Ожидает ответа",
            "scheduled": "Принята",
            "active": "Идёт",
            "finished": "Завершена",
            "cancelled": "Отменена",
        }
        lines = ["⚔️ <b>Войны клана</b>"]
        for war in wars[:10]:
            extra = []
            if war.get("score_for") is not None:
                extra.append(f"счёт {war.get('score_for', 0)}:{war.get('score_against', 0)}")
            if war.get("incoming"):
                extra.append("входящий вызов")
            lines.append(
                f"• <b>[{escape(str(war.get('opponent_tag') or '—'))}] "
                f"{escape(str(war.get('opponent') or 'Клан'))}</b> — "
                f"{status_labels.get(str(war.get('status')), str(war.get('status') or '—'))}"
                + (f" · {' · '.join(extra)}" if extra else "")
                + f"\n  ID: <code>{escape(str(war.get('id') or ''))}</code>"
            )
        lines.append(
            "\nКоманды: /клан война создать КЛАН · /клан война принять ID · "
            "/клан война отклонить ID · /клан война начать ID · "
            "/клан война завершить ID СЧЁТ_A СЧЁТ_B"
        )
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if sub in {"новости", "объявления", "news"}:
        result = await bot_get_clan_info(message.from_user.id)
        if result.error or not isinstance(result.data, dict):
            await message.answer("❌ Не удалось получить объявления.")
            return
        if result.data.get("error") == "NO_CLAN":
            await message.answer("ℹ️ Вы не состоите в клане.")
            return
        announcements = result.data.get("announcements") or []
        if not announcements:
            await message.answer("ℹ️ У клана пока нет объявлений.")
            return
        lines = [f"📣 <b>Объявления [{escape(str(result.data.get('tag') or '—'))}] {escape(str(result.data.get('name') or 'Клан'))}</b>"]
        for item in announcements[:10]:
            author = item.get("author_nickname") or "Система PRISMA"
            lines.append(
                f"\n<b>{escape(str(item.get('title') or 'Без заголовка'))}</b> · "
                f"{escape(str(author))}\n{escape(str(item.get('body') or ''))}"
            )
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if sub in {"объявить", "объявление", "announce"}:
        title = " ".join(args[1:]).strip()
        body = multiline.strip()
        if not title or not body:
            await message.answer(
                "❌ Формат: /клан объявить Заголовок\n"
                "Текст объявления"
            )
            return
        result = await bot_create_clan_announcement(message.from_user.id, title, body)
        if result.error:
            error = safe_rpc_error(result)
            messages = {
                "NO_CLAN_PERMISSION": "❌ Объявления может публиковать только владелец или офицер клана.",
                "NO_CLAN": "❌ Вы не состоите в клане.",
                "INVALID_ANNOUNCEMENT": "❌ Заголовок: 3–120 символов, текст: 3–3000 символов.",
            }
            await message.answer(messages.get(error, "❌ Не удалось опубликовать объявление."))
            return
        await message.answer("✅ Объявление опубликовано.")
        return

    if sub in {"приглашения", "заявки", "invites"}:
        result = await bot_list_clan_invites(message.from_user.id)
        if result.error or not isinstance(result.data, dict):
            await message.answer("❌ Не удалось получить приглашения.")
            return
        invites = result.data.get("invites") or []
        if not invites:
            await message.answer("ℹ️ Активных приглашений нет.")
            return
        lines = ["⚔️ <b>Приглашения в кланы</b>"]
        for invite in invites[:10]:
            lines.append(
                f"• <b>[{escape(str(invite.get('tag') or '—'))}] "
                f"{escape(str(invite.get('name') or 'Клан'))}</b> · "
                f"от {escape(str(invite.get('inviter_nickname') or 'Участник PRISMA'))}\n"
                f"  Принять: <code>/клан принять {escape(str(invite.get('id') or ''))}</code>\n"
                f"  Отклонить: <code>/клан отклонить {escape(str(invite.get('id') or ''))}</code>"
            )
        await message.answer("\n".join(lines), parse_mode="HTML")
        return

    if sub in {"принять", "accept"}:
        if len(args) < 2:
            await message.answer("❌ Пример: /клан принять ID_приглашения")
            return
        result = await bot_accept_clan_invite(message.from_user.id, args[1].strip())
        if result.error:
            error = str(result.error)
            messages = {
                "INVITE_NOT_FOUND": "❌ Приглашение не найдено или уже недействительно.",
                "USER_ALREADY_IN_CLAN": "❌ Вы уже состоите в клане.",
            }
            await message.answer(messages.get(error, "❌ Не удалось принять приглашение."))
            return
        data = result.data if isinstance(result.data, dict) else {}
        await message.answer(
            f"✅ Вы вступили в клан <b>[{escape(str(data.get('tag') or '—'))}] "
            f"{escape(str(data.get('name') or 'Клан'))}</b>.",
            parse_mode="HTML",
        )
        return

    if sub in {"отклонить", "отказать", "deny"}:
        if len(args) < 2:
            await message.answer("❌ Пример: /клан отклонить ID_приглашения")
            return
        result = await bot_decline_clan_invite(message.from_user.id, args[1].strip())
        if result.error:
            await message.answer("❌ Приглашение не найдено или уже недействительно.")
            return
        await message.answer("✅ Приглашение отклонено.")
        return

    if sub in {"пригласить", "invite"}:
        if len(args) < 2:
            await message.answer("❌ Пример: /клан пригласить Minecraft_ник")
            return
        target = args[1].strip()
        result = await bot_clan_invite(message.from_user.id, target)
        if result.error:
            error = str(result.error)
            messages = {
                "NO_CLAN": "❌ Вы не состоите в клане.",
                "NO_CLAN_PERMISSION": "❌ Приглашать игроков может только владелец или офицер клана.",
                "PLAYER_NOT_FOUND": "❌ Игрок с таким Minecraft-ником не найден.",
                "PLAYER_ALREADY_IN_CLAN": "❌ Этот игрок уже состоит в клане.",
                "CANNOT_INVITE_SELF": "❌ Нельзя пригласить самого себя.",
                "INVITE_ALREADY_EXISTS": "❌ У этого игрока уже есть активное приглашение.",
            }
            await message.answer(messages.get(error, "❌ Не удалось отправить приглашение."))
            return
        await message.answer(f"✅ Приглашение отправлено игроку <b>{escape(target)}</b>.", parse_mode="HTML")
        return

    if sub in {"роль", "role", "назначить"}:
        if len(args) < 3:
            await message.answer(
                "❌ Пример: /клан роль Minecraft_ник офицер\n"
                "Роли: совладелец, офицер, участник, рекрут."
            )
            return
        target = args[1].strip()
        aliases = {
            "совладелец": "co_owner",
            "co_owner": "co_owner",
            "co-owner": "co_owner",
            "заместитель": "co_owner",
            "офицер": "officer",
            "officer": "officer",
            "участник": "member",
            "member": "member",
            "рекрут": "recruit",
            "recruit": "recruit",
        }
        role = aliases.get(args[2].casefold())
        if role is None:
            await message.answer("❌ Неизвестная роль. Используйте: совладелец, офицер, участник или рекрут.")
            return
        result = await bot_set_clan_role(message.from_user.id, target, role)
        if result.error:
            error = str(result.error)
            messages = {
                "NO_CLAN": "❌ Вы не состоите в клане.",
                "NO_CLAN_PERMISSION": "❌ У вас нет права изменять эту роль.",
                "OWNER_ONLY": "❌ Это действие доступно только владельцу.",
                "PLAYER_NOT_FOUND": "❌ Игрок с таким Minecraft-ником не найден.",
                "TARGET_NOT_IN_CLAN": "❌ Игрок не состоит в вашем клане.",
                "TARGET_INVALID_ROLE": "❌ Нельзя управлять ролью равного или более высокого уровня.",
                "CANNOT_MANAGE_SELF": "❌ Нельзя изменять собственную роль.",
                "INVALID_ROLE": "❌ Указана некорректная роль.",
                "ROLE_UNCHANGED": "ℹ️ У игрока уже установлена эта роль.",
            }
            await message.answer(messages.get(error, "❌ Не удалось изменить роль."))
            return
        labels = {
            "co_owner": "Совладелец",
            "officer": "Офицер",
            "member": "Участник",
            "recruit": "Рекрут",
        }
        await message.answer(
            f"✅ Роль игрока <b>{escape(target)}</b> изменена на <b>{labels[role]}</b>.",
            parse_mode="HTML",
        )
        return

    if sub in {"вступить", "join"}:
        name = " ".join(args[1:]).strip()
        if not name:
            await message.answer("❌ Пример: /клан вступить Название или /клан вступить 1")
            return
        if name.isdigit():
            clan_result = await bot_get_clan_by_position(int(name))
            if clan_result.error or not isinstance(clan_result.data, dict) or clan_result.data.get("error"):
                await message.answer("❌ Клан с таким номером не найден.")
                return
            name = str(clan_result.data.get("name") or "")
        result = await bot_join_clan(message.from_user.id, name)
        if result.error:
            error = str(result.error)
            messages = {
                "CLAN_NOT_FOUND": "❌ Клан не найден.",
                "USER_ALREADY_IN_CLAN": "❌ Вы уже состоите в клане.",
                "USER_NOT_ALLOWED": "⏳ Доступ к кланам будет после одобрения заявки.",
            }
            await message.answer(messages.get(error, "❌ Не удалось вступить в клан."))
            return
        await message.answer(f"✅ Вы вступили в клан <b>{escape(str((result.data or {}).get('name') or name))}</b>.", parse_mode="HTML")
        return

    if sub in {"выйти", "покинуть", "leave"}:
        result = await bot_leave_clan(message.from_user.id)
        if result.error:
            error = str(result.error)
            messages = {
                "NO_CLAN": "⚔️ Вы не состоите в клане.",
            }
            await message.answer(messages.get(error, "❌ Не удалось выйти из клана."))
            return
        await message.answer("✅ Вы вышли из клана.")
        return

    if sub in {"удалить", "распустить", "delete", "disband"}:
        result = await bot_disband_clan(message.from_user.id)
        if result.error:
            error = str(result.error)
            messages = {
                "OWNER_ONLY": "❌ Распустить клан может только владелец.",
                "NO_CLAN": "⚔️ У вас нет клана.",
            }
            await message.answer(messages.get(error, "❌ Не удалось распустить клан."))
            return
        await message.answer("✅ Клан распущен.")
        return

    await my_clan_command(message)


@router.message(F.text.regexp(r"(?i)^клан\s+.+$"))
async def plain_clan_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    raw = (message.text or "").strip()
    clone = message.model_copy(update={"text": "/" + raw})
    await clan_group_command(clone)


@router.message(Command("мой", "мои"))
async def my_commands_group(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    if args and args[0].casefold() in {"варны", "варн", "преды", "предупреждения"}:
        clone = message.model_copy(update={"text": "/варны " + " ".join(args[1:])})
        await warns_command(clone)
        return
    if args and args[0].casefold() in {"отн", "отношения"}:
        info = await bot_social_info(message.from_user.id)
        if info.error or not isinstance(info.data, dict):
            await message.answer("❌ Не удалось получить социальный статус.")
        else:
            await message.answer(social_info_message(info.data, "RELATIONSHIP"), parse_mode="HTML")
        return
    if args and args[0].casefold() in {"брак", "брак?"}:
        info = await bot_social_info(message.from_user.id)
        if info.error or not isinstance(info.data, dict):
            await message.answer("❌ Не удалось получить социальный статус.")
        else:
            await message.answer(social_info_message(info.data, "MARRIAGE"), parse_mode="HTML")
        return
    await message.answer("ℹ️ Примеры: /мойклан, /мои варны, /мои отн, /мой брак")


async def _social_target(message: types.Message, args: list[str]):
    target, rest = await _resolve_target(message, args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return None, rest
    if int(target.get("tg_id") or 0) == message.from_user.id:
        await message.answer("❌ Нельзя выбрать себя.")
        return None, rest
    return target, rest


@router.message(Command("браки", "marriages"))
async def marriages_list_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_list_marriages()
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список браков.")
        return
    if not result.data:
        await message.answer("💍 В PRISMA пока нет активных браков.")
        return
    active = [row for row in result.data if str(row.get("status") or "").upper() == "ACTIVE"]
    archived = [row for row in result.data if str(row.get("status") or "").upper() == "ARCHIVED"]
    lines=["💍 <b>Браки</b>"]
    if active:
        lines.append("🫶 <b>PRISMA</b>")
        for number,row in enumerate(active,1):
            a=_mention(row.get("user_a"),row.get("user_a_name"),row.get("user_a_username"))
            b=_mention(row.get("user_b"),row.get("user_b_name"),row.get("user_b_username"))
            married_at=_parse_timestamp(row.get("married_at"))
            source_duration = str(row.get("duration_text") or "").strip()
            duration = f" ({escape(source_duration)})" if source_duration else (f" ({_elapsed_label(married_at)})" if married_at else "")
            lines.append(f"{number}. {a} + {b}{duration}")
    await message.answer("\n".join(lines),parse_mode="HTML")


@router.message(F.text.regexp(r"(?i)^браки$"))
async def plain_marriages_list_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    clone=message.model_copy(update={"text":"/браки"})
    await marriages_list_command(clone)


@router.message(Command("отн", "отношения", "relationship"))
async def relationship_command(message: types.Message):
    await handle_social(message, "RELATIONSHIP")


@router.message(Command("брак", "marriage"))
async def marriage_command(message: types.Message):
    await handle_social(message, "MARRIAGE")


@router.message(Command("развод", "divorce"))
async def divorce_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    result = await bot_social_end(message.from_user.id, "MARRIAGE")
    if result.error:
        await message.answer("ℹ️ Активного брака нет.")
        return
    await message.answer("✅ Брак расторгнут.")


@router.message(Command("чат", "chat"))
async def chat_info_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    if args and args[0].casefold() not in {"инфо", "info"}:
        await message.answer("ℹ️ Пример: /чат инфо")
        return
    try:
        count = await message.bot.get_chat_member_count(message.chat.id)
        chat = await message.bot.get_chat(message.chat.id)
    except Exception:
        await message.answer("❌ Не удалось получить информацию о чате.")
        return
    await message.answer(
        f"💬 <b>Информация о чате</b>\n"
        f"Название: <b>{escape(str(chat.title or 'PRISMA'))}</b>\n"
        f"ID: <code>{chat.id}</code>\n"
        f"Участников: <b>{count}</b>",
        parse_mode="HTML",
    )


@router.message(F.text.regexp(r"^[+-]чат$"))
async def toggle_chat_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    if not await _chat_admin(message):
        return
    if not await _bot_can_restrict(message):
        await message.answer("❌ У Prisma нет права изменять права участников в этом чате.")
        return

    enabled = (message.text or "").strip().startswith("+")
    permissions = ChatPermissions(
        can_send_messages=enabled,
        can_send_audios=enabled,
        can_send_documents=enabled,
        can_send_photos=enabled,
        can_send_videos=enabled,
        can_send_video_notes=enabled,
        can_send_voice_notes=enabled,
        can_send_polls=enabled,
        can_send_other_messages=enabled,
        can_add_web_page_previews=enabled,
    )
    try:
        await message.bot.set_chat_permissions(
            message.chat.id,
            permissions=permissions,
            use_independent_chat_permissions=True,
        )
    except Exception:
        await message.answer("❌ Не удалось изменить режим чата. Проверьте права Prisma.")
        return

    if enabled:
        await message.answer("🔓 <b>Чат открыт.</b> Теперь писать могут все участники.", parse_mode="HTML")
    else:
        await message.answer("🔒 <b>Чат закрыт.</b> Теперь писать могут только администраторы.", parse_mode="HTML")


@router.message(Command("население", "population"))
async def population_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    try:
        count = await message.bot.get_chat_member_count(message.chat.id)
    except Exception:
        await message.answer("❌ Не удалось узнать количество участников.")
        return
    await message.answer(f"👥 В чате сейчас <b>{count}</b> участников.", parse_mode="HTML")


@router.message(Command("смс_ид", "msg_id"))
async def message_id_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    if not message.reply_to_message:
        await message.answer("❌ Используйте команду ответом на сообщение.")
        return
    await message.answer(
        f"🆔 ID сообщения: <code>{message.reply_to_message.message_id}</code>",
        parse_mode="HTML",
    )


@router.message(Command("ид", "id"))
async def user_id_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    if message.reply_to_message and message.reply_to_message.from_user:
        target_id = message.reply_to_message.from_user.id
        name = message.reply_to_message.from_user.full_name
    elif args:
        target, _ = await _resolve_target(message, args)
        if not target:
            await message.answer("❌ Пользователь не найден.")
            return
        target_id = target.get("tg_id")
        name = target.get("full_name") or target.get("username") or target_id
    else:
        target_id = message.from_user.id
        name = message.from_user.full_name
    await message.answer(
        f"🆔 <b>{escape(str(name))}</b>: <code>{target_id}</code>",
        parse_mode="HTML",
    )


@router.message(Command("кто_онлайн", "online"))
async def online_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    minutes = 10
    if args and args[0].isdigit():
        minutes = max(1, min(60, int(args[0])))
    result = await bot_active_chat_users(message.chat.id, minutes, 50)
    if result.error or not isinstance(result.data, list):
        await message.answer("❌ Не удалось получить список активных.")
        return
    if not result.data:
        await message.answer(f"🟢 За последние {minutes} мин. сообщений не было.")
        return
    lines = [f"🟢 <b>Активны за {minutes} мин.</b>"]
    for row in result.data:
        name = row.get("telegram_username") or row.get("full_name") or row.get("tg_id")
        lines.append(f"• {escape(str(name))}")
    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("актив", "active"))
async def active_command(message: types.Message):
    await online_command(message)


@router.message(F.text.regexp(r"(?i)^актив(?:\s+\d+)?$"))
async def plain_active_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    raw = (message.text or "").strip()
    clone = message.model_copy(update={"text": "/" + raw})
    await active_command(clone)


@router.message(Command("скажи", "say"))
async def say_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, multiline = _first_line(message.text or "")
    text = multiline or " ".join(args)
    if not text:
        await message.answer("❌ Укажите текст.")
        return
    await message.answer(escape(text[:3500]), parse_mode="HTML")


@router.message(Command("выбери", "choose"))
async def choose_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, multiline = _first_line(message.text or "")
    raw = multiline or " ".join(args)
    options = [x.strip() for x in re.split(r"\s+или\s+", raw, flags=re.I) if x.strip()]
    if len(options) < 2:
        await message.answer("❌ Пример: /выбери левое или правое")
        return
    await message.answer(f"🎯 Я выбираю: <b>{escape(random.choice(options))}</b>", parse_mode="HTML")


@router.message(Command("инфа", "chance"))
async def chance_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, multiline = _first_line(message.text or "")
    raw = multiline or " ".join(args)
    if not raw:
        await message.answer("❌ Пример: /инфа построится ли город")
        return
    await message.answer(f"🔮 Шанс: <b>{random.randint(0,100)}%</b>", parse_mode="HTML")


@router.message(Command("жребий", "draw"))
async def draw_command(message: types.Message):
    if not _is_prisma_chat(message):
        return
    args, _ = _first_line(message.text or "")
    targets = []
    if message.reply_to_message and message.reply_to_message.from_user:
        targets.append(message.reply_to_message.from_user)
    for token in args:
        target, _ = await _resolve_target(message, [token])
        if target:
            targets.append(target)
    if not targets:
        await message.answer("❌ Укажите пользователей или используйте ответ на сообщение.")
        return
    if len(targets) == 1:
        await message.answer(f"🎟 Жребий пал на <b>{escape(str(targets[0].get('full_name') or targets[0].get('username') or targets[0].get('tg_id')))}</b>.", parse_mode="HTML")
        return
    chosen = random.choice(targets)
    if isinstance(chosen, dict):
        name = chosen.get("full_name") or chosen.get("username") or chosen.get("tg_id")
    else:
        name = chosen.full_name
    await message.answer(f"🎟 Жребий пал на <b>{escape(str(name))}</b>.", parse_mode="HTML")


STAFF_ROLE_ALIASES = {
    "owner": "owner",
    "владелец": "owner",
    "влд": "owner",
    "head_admin": "head_admin",
    "headadmin": "head_admin",
    "главныйадмин": "head_admin",
    "га": "head_admin",
    "head_staff": "head_staff",
    "headmod": "head_staff",
    "главамодерации": "head_staff",
    "гс": "head_staff",
    "admin": "admin",
    "администратор": "admin",
    "адм": "admin",
    "senior_moderator": "senior_moderator",
    "senior": "senior_moderator",
    "старшиймодератор": "senior_moderator",
    "смдр": "senior_moderator",
    "moderator": "moderator",
    "модератор": "moderator",
    "мдр": "moderator",
    "helper": "helper",
    "хелпер": "helper",
    "хелп": "helper",
    "developer": "developer",
    "tech": "developer",
    "тех": "developer",
    "builder": "builder",
    "строитель": "builder",
    "стр": "builder",
    "game_designer": "game_designer",
    "gamedesigner": "game_designer",
    "дизайнер": "game_designer",
    "gd": "game_designer",
    "event_manager": "event_manager",
    "event": "event_manager",
    "ивент": "event_manager",
    "ивт": "event_manager",
    "media": "media",
    "blogger": "media",
    "медиа": "media",
}

STAFF_ROLE_LABELS = {
    "owner": "Owner · Владелец",
    "head_admin": "Co-Owner / Head Admin",
    "head_staff": "Head of Staff / Head Mod",
    "admin": "Administrator",
    "senior_moderator": "Senior Moderator",
    "moderator": "Moderator",
    "helper": "Helper / Trainee",
    "developer": "Developer / Tech Admin",
    "builder": "Builder / Map Maker",
    "game_designer": "Game Designer / Content Creator",
    "event_manager": "Event Manager",
    "media": "Media / Blogger",
}

async def _set_staff_role_command(message: types.Message):
    if not _is_prisma_chat(message) or not await _chat_admin(message):
        return

    args, _ = _first_line(message.text or "")
    if not args:
        await message.answer(
            "ℹ️ Использование: /staff <роль> <пользователь>\n"
            "Роли: owner, head_admin, head_staff, admin, senior_moderator, moderator, helper, "
            "developer, builder, game_designer, event_manager, media."
        )
        return

    requested = args[0].casefold().replace("-", "_").replace(" ", "")
    role = STAFF_ROLE_ALIASES.get(requested)
    if role is None:
        if requested in {"remove", "снять", "разжаловать"}:
            target, _ = await _resolve_target(message, args[1:])
            if not target:
                await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
                return
            result = await bot_remove_staff(message.from_user.id, int(target["tg_id"]))
            if result.error:
                errors = {
                    "ADMIN_LACKS_PERMISSION": "❌ Недостаточно прав.",
                    "STAFF_HIERARCHY_FORBIDS": "❌ Нельзя изменить роль равного или более высокого уровня.",
                    "TARGET_NOT_STAFF": "❌ Пользователь не состоит в PRISMA staff.",
                    "SELF_STAFF_ASSIGNMENT": "❌ Нельзя снять роль с себя.",
                    "SELF_REMOVE_FORBIDDEN": "❌ Нельзя снять роль с себя.",
                    "STAFF_BRANCH_FORBIDS": "❌ Эта роль находится вне вашей ветки управления.",
                }
                await message.answer(errors.get(str(result.error), "❌ Не удалось снять роль."))
                return
            await message.answer(f"✅ Роль снята с <b>{_name(target)}</b>.", parse_mode="HTML")
            return

        await message.answer("❌ Неизвестная роль. Используйте /staff для списка ролей.")
        return

    target, _ = await _resolve_target(message, args[1:])
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return

    result = await bot_set_staff_role(message.from_user.id, int(target["tg_id"]), role)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        error = str(result.error or (result.data or {}).get("error") or result.data)
        errors = {
            "ADMIN_LACKS_PERMISSION": "❌ Недостаточно прав для управления staff.",
            "STAFF_HIERARCHY_FORBIDS": "❌ Нельзя назначить равный или более высокий уровень.",
            "STAFF_BRANCH_FORBIDS": "❌ Head of Staff может управлять только модерационной веткой.",
            "OWNER_ONLY": "❌ Назначение Owner доступно только Owner.",
            "USER_NOT_FOUND": "❌ Пользователь не найден.",
            "SELF_STAFF_ASSIGNMENT": "❌ Нельзя назначить роль самому себе.",
        }
        await message.answer(errors.get(error, "❌ Не удалось изменить роль."))
        return

    label = STAFF_ROLE_LABELS.get(role, role)
    await message.answer(
        f"✅ <b>{_name(target)}</b> теперь <b>{escape(label)}</b>.",
        parse_mode="HTML",
    )

@router.message(Command("staff", "персонал"))
async def staff_role_command(message: types.Message):
    await _set_staff_role_command(message)


STAFF_NUMERIC_ROLES = [
    (0.5, "helper"),
    (1.0, "moderator"),
    (2.0, "senior_moderator"),
    (3.0, "admin"),
    (3.5, "head_staff"),
    (4.0, "head_admin"),
    (5.0, "owner"),
]

def _staff_role_for_rank(rank: float) -> str | None:
    for value, role in STAFF_NUMERIC_ROLES:
        if abs(value - rank) < 0.001:
            return role
    return None

async def _set_staff_command(message: types.Message, mode: str):
    if not _is_prisma_chat(message) or not await _chat_admin(message):
        return

    args, _ = _first_line(message.text or "")
    target_args = args
    requested_rank: float | None = None

    if mode == "set":
        if args:
            try:
                requested_rank = float(args[0].replace(",", "."))
                target_args = args[1:]
            except ValueError:
                requested_rank = None

        if requested_rank is None:
            requested_rank = 1.0

    target, _ = await _resolve_target(message, target_args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return

    target_id = int(target["tg_id"])

    if mode in {"promote", "demote"}:
        staff = await bot_list_staff()
        rows = staff.data if not staff.error and isinstance(staff.data, list) else []
        current = next(
            (float(x.get("rank")) for x in rows if int(x.get("tg_id") or 0) == target_id and x.get("rank") is not None),
            0.0,
        )
        ranks = [value for value, _ in STAFF_NUMERIC_ROLES]
        if current <= 0:
            if mode == "promote":
                requested_rank = ranks[0]
            else:
                await message.answer("❌ Пользователь не состоит в PRISMA staff.")
                return
        else:
            try:
                pos = min(range(len(ranks)), key=lambda i: abs(ranks[i] - current))
            except ValueError:
                pos = 0
            next_pos = pos + (1 if mode == "promote" else -1)
            if next_pos < 0:
                requested_rank = 0.0
            elif next_pos >= len(ranks):
                requested_rank = ranks[-1]
            else:
                requested_rank = ranks[next_pos]

    if requested_rank is None or requested_rank <= 0:
        result = await bot_remove_staff(message.from_user.id, target_id)
        if result.error:
            errors = {
                "ADMIN_LACKS_PERMISSION": "❌ Недостаточно прав.",
                "STAFF_HIERARCHY_FORBIDS": "❌ Нельзя изменить роль равного или более высокого уровня.",
                "TARGET_NOT_STAFF": "❌ Пользователь не состоит в PRISMA staff.",
                "SELF_STAFF_ASSIGNMENT": "❌ Нельзя снять роль с себя.",
                "SELF_REMOVE_FORBIDDEN": "❌ Нельзя снять роль с себя.",
            }
            await message.answer(errors.get(str(result.error), "❌ Не удалось снять роль."))
            return
        await message.answer(f"✅ Роль снята с <b>{_name(target)}</b>.", parse_mode="HTML")
        return

    role = _staff_role_for_rank(requested_rank)
    if role is None:
        await message.answer("❌ Допустимые уровни: 0.5, 1, 2, 3, 3.5, 4, 5.")
        return

    result = await bot_set_staff_role(message.from_user.id, target_id, role)
    if result.error or not isinstance(result.data, dict) or not result.data.get("success"):
        error = str(result.error or (result.data or {}).get("error") or result.data)
        errors = {
            "ADMIN_LACKS_PERMISSION": "❌ Недостаточно прав для управления staff.",
            "STAFF_HIERARCHY_FORBIDS": "❌ Нельзя назначить равный или более высокий уровень.",
            "STAFF_BRANCH_FORBIDS": "❌ Head of Staff может управлять только модерационной веткой.",
            "OWNER_ONLY": "❌ Назначение Owner доступно только Owner.",
            "USER_NOT_FOUND": "❌ Пользователь не найден.",
            "SELF_STAFF_ASSIGNMENT": "❌ Нельзя назначить роль самому себе.",
        }
        await message.answer(errors.get(error, "❌ Не удалось изменить роль."))
        return

    label = STAFF_ROLE_LABELS.get(role, role)
    rank_label = escape(str(result.data.get("rank_label") or requested_rank).replace(".", ","))
    await message.answer(
        f"✅ <b>{_name(target)}</b> теперь <b>{escape(label)}</b> · уровень <b>{rank_label}</b>.",
        parse_mode="HTML",
    )

@router.message(Command("модер", "модерка"))
async def assign_staff_command(message: types.Message):
    await _set_staff_command(message, "set")


@router.message(Command("повысить", "promote"))
async def promote_staff_command(message: types.Message):
    await _set_staff_command(message, "promote")


@router.message(Command("понизить", "demote"))
async def demote_staff_command(message: types.Message):
    await _set_staff_command(message, "demote")


@router.message(Command("снять", "разжаловать"))
async def remove_staff_command(message: types.Message):
    await _set_staff_command(message, "remove")
