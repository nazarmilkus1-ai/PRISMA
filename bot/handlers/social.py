from __future__ import annotations

from html import escape
from utils.errors import safe_rpc_error
from uuid import UUID

from aiogram import F, Router, types
from aiogram.filters import Command

from db.rpc import (
    bot_find_user,
    bot_social_cancel,
    bot_social_end,
    bot_social_info,
    bot_social_request,
    bot_social_respond,
    bot_touch_user,
)

router = Router(name="social_commands")


def _is_prisma_chat(message: types.Message) -> bool:
    return message.chat.type in {"group", "supergroup"}


async def _resolve_target(message: types.Message, args: list[str]):
    reply = message.reply_to_message
    if reply and reply.from_user and not reply.from_user.is_bot:
        user = reply.from_user
        await bot_touch_user(
            user.id,
            user.username or "",
            user.first_name or "",
            user.last_name or "",
            user.full_name,
            "GROUP",
        )
        return {
            "tg_id": user.id,
            "username": user.username,
            "full_name": user.full_name,
            "minecraft_nick": None,
        }

    if not args:
        return None

    result = await bot_find_user(args[0])
    if result.error or not isinstance(result.data, dict) or result.data.get("error"):
        return None

    target = dict(result.data)
    if "tg_id" not in target:
        return None
    target.setdefault("minecraft_nick", target.get("minecraft_nickname"))
    target.setdefault("username", target.get("telegram_username"))
    return target


def _display_name(target: dict) -> str:
    return escape(
        str(
            target.get("minecraft_nick")
            or target.get("minecraft_nickname")
            or target.get("username")
            or target.get("full_name")
            or target.get("tg_id")
            or "пользователь"
        )
    )


def _request_id(args: list[str], usage: str) -> str | None:
    if len(args) < 2 or not args[1].strip():
        return None
    return args[1].strip()


def social_info_message(data: dict, kind: str) -> str:
    kind_title = "Брак" if kind == "MARRIAGE" else "Отношения"
    current_key = "marriage" if kind == "MARRIAGE" else "relationship"
    incoming_key = "marriage_requests_in" if kind == "MARRIAGE" else "relationship_requests_in"
    outgoing_key = "marriage_requests_out" if kind == "MARRIAGE" else "relationship_requests_out"

    current = data.get(current_key)
    lines = [
        f"{'💍' if kind == 'MARRIAGE' else '❤️'} {kind_title}: "
        + (
            f"активны с <b>{escape(str(current.get('partner_nickname') or current.get('partner_tg_id') or 'Игрок'))}</b>."
            if isinstance(current, dict)
            else "нет."
        )
    ]

    incoming = data.get(incoming_key) if isinstance(data.get(incoming_key), list) else []
    outgoing = data.get(outgoing_key) if isinstance(data.get(outgoing_key), list) else []

    if incoming:
        lines.append("📥 Входящие:")
        for row in incoming:
            lines.append(
                f"• <b>{escape(str(row.get('requester_nickname') or 'Игрок'))}</b> · "
                f"<code>{escape(str(row.get('id') or '—'))}</code>"
            )
    if outgoing:
        lines.append("📤 Отправленные:")
        for row in outgoing:
            lines.append(
                f"• <b>{escape(str(row.get('target_nickname') or 'Игрок'))}</b> · "
                f"<code>{escape(str(row.get('id') or '—'))}</code>"
            )
    if not incoming and not outgoing:
        lines.append("Заявок нет.")

    if kind == "MARRIAGE":
        lines.extend([
            "",
            "Новое предложение: /брак @ник",
            "Принять: /брак принять ID",
            "Отклонить: /брак отклонить ID",
            "Отменить своё: /брак отменить ID",
            "Расторгнуть: /брак развод",
        ])
    else:
        lines.extend([
            "",
            "Новая заявка: /отн @ник",
            "Принять: /отн принять ID",
            "Отклонить: /отн отклонить ID",
            "Отменить свою: /отн отменить ID",
            "Завершить: /отн завершить",
        ])
    return "\n".join(lines)


async def handle_social(message: types.Message, kind: str):
    if not _is_prisma_chat(message):
        return

    # Drop the "/command" token (and a possible @botname suffix); the rest are arguments.
    args = (message.text or "").split()[1:]
    sub = args[0].casefold() if args else ""
    control_accept = {"принять", "accept"}
    control_reject = {"отклонить", "reject"}
    control_cancel = {"отменить", "cancel"}
    control_end = {"развод", "развестись", "divorce"} if kind == "MARRIAGE" else {"завершить", "разорвать", "расстаться", "end"}

    if sub in control_accept:
        request_id = _request_id(args, "")
        if not request_id:
            await message.answer(f"❌ Укажите ID: /{'брак' if kind == 'MARRIAGE' else 'отн'} принять ID")
            return
        result = await bot_social_respond(message.from_user.id, kind, request_id, True)
        errors = {
            "MARRIAGE_REQUEST_NOT_FOUND": "❌ Предложение не найдено или уже обработано.",
            "RELATIONSHIP_REQUEST_NOT_FOUND": "❌ Заявка не найдена или уже обработана.",
            "ALREADY_MARRIED": "❌ Один из пользователей уже состоит в браке.",
            "ALREADY_IN_RELATIONSHIP": "❌ Один из пользователей уже состоит в отношениях.",
            "PLAYER_ACCESS_REQUIRED": "❌ Действие доступно только участникам PRISMA.",
        }
        await message.answer(errors.get(str(result.error), "✅ Запрос обработан." if not result.error else "❌ Не удалось принять запрос."))
        return

    if sub in control_reject:
        request_id = _request_id(args, "")
        if not request_id:
            await message.answer(f"❌ Укажите ID: /{'брак' if kind == 'MARRIAGE' else 'отн'} отклонить ID")
            return
        result = await bot_social_respond(message.from_user.id, kind, request_id, False)
        not_found = "MARRIAGE_REQUEST_NOT_FOUND" if kind == "MARRIAGE" else "RELATIONSHIP_REQUEST_NOT_FOUND"
        await message.answer(
            "✅ Запрос отклонён."
            if not result.error
            else ("❌ Запрос не найден или уже обработан." if str(result.error) == not_found else "❌ Не удалось отклонить запрос.")
        )
        return

    if sub in control_cancel:
        request_id = _request_id(args, "")
        if not request_id:
            await message.answer(f"❌ Укажите ID: /{'брак' if kind == 'MARRIAGE' else 'отн'} отменить ID")
            return
        result = await bot_social_cancel(message.from_user.id, kind, request_id)
        not_found = "MARRIAGE_REQUEST_NOT_FOUND" if kind == "MARRIAGE" else "RELATIONSHIP_REQUEST_NOT_FOUND"
        await message.answer(
            "✅ Запрос отменён."
            if not result.error
            else ("❌ Исходящий запрос не найден или уже обработан." if str(result.error) == not_found else "❌ Не удалось отменить запрос.")
        )
        return

    if sub in control_end:
        result = await bot_social_end(message.from_user.id, kind)
        if result.error:
            await message.answer("ℹ️ Активного статуса нет.")
            return
        await message.answer("✅ Статус завершён." if kind != "MARRIAGE" else "✅ Брак расторгнут.")
        return

    if sub in {"да", "нет", "yes", "no"}:
        await message.answer(
            f"⚠️ Теперь запросы подтверждаются по ID: /{'брак' if kind == 'MARRIAGE' else 'отн'} "
            f"{'принять' if sub in {'да', 'yes'} else 'отклонить'} ID"
        )
        return

    info = await bot_social_info(message.from_user.id)
    if info.error or not isinstance(info.data, dict):
        await message.answer("❌ Не удалось получить социальный статус.")
        return

    if not sub or sub in {"мой", "статус", "status"}:
        await message.answer(social_info_message(info.data, kind), parse_mode="HTML")
        return

    request_aliases = {"предложить", "запрос", "request"} if kind == "MARRIAGE" else {"запрос", "request"}
    target_args = args[1:] if sub in request_aliases else args
    target = await _resolve_target(message, target_args)
    if not target:
        await message.answer("❌ Укажите пользователя или ответьте на его сообщение.")
        return

    result = await bot_social_request(message.from_user.id, int(target["tg_id"]), kind)
    errors = {
        "PLAYER_ACCESS_REQUIRED": "❌ Оба пользователя должны быть участниками PRISMA.",
        "SELF_TARGET_FORBIDDEN": "❌ Нельзя выбрать себя.",
        "ALREADY_MARRIED": "❌ Один из пользователей уже состоит в браке.",
        "ALREADY_IN_RELATIONSHIP": "❌ Один из пользователей уже состоит в отношениях.",
        "MARRIAGE_REQUEST_ALREADY_SENT": "⚠️ Предложение уже отправлено.",
        "INCOMING_MARRIAGE_REQUEST_EXISTS": "⚠️ У пользователя уже есть встречное предложение.",
        "RELATIONSHIP_REQUEST_ALREADY_SENT": "⚠️ Заявка уже отправлена.",
        "INCOMING_RELATIONSHIP_REQUEST_EXISTS": "⚠️ У пользователя уже есть встречная заявка.",
    }
    if result.error:
        await message.answer(errors.get(str(result.error), "❌ Не удалось отправить запрос."))
        return

    data = result.data if isinstance(result.data, dict) else {}
    request_id = escape(str(data.get("request_id") or "—"))
    target_name = _display_name(target)
    if kind == "MARRIAGE":
        await message.answer(
            f"💍 Предложение отправлено пользователю <b>{target_name}</b>.\nID: <code>{request_id}</code>",
            parse_mode="HTML",
        )
    else:
        await message.answer(
            f"❤️ Заявка отправлена пользователю <b>{target_name}</b>.\nID: <code>{request_id}</code>",
            parse_mode="HTML",
        )


@router.callback_query(F.data.startswith("social:"))
async def social_request_callback(callback: types.CallbackQuery):
    parts = (callback.data or "").split(":")
    if len(parts) != 4 or parts[1] not in {"accept", "reject"} or parts[2] not in {"M", "R"}:
        await callback.answer("Некорректная социальная заявка.", show_alert=True)
        return

    try:
        request_id = str(UUID(parts[3]))
    except ValueError:
        await callback.answer("Некорректный ID заявки.", show_alert=True)
        return

    kind = "MARRIAGE" if parts[2] == "M" else "RELATIONSHIP"
    accept = parts[1] == "accept"
    result = await bot_social_respond(callback.from_user.id, kind, request_id, accept)

    if result.error:
        error = safe_rpc_error(result)
        if kind == "MARRIAGE":
            text = {
                "MARRIAGE_REQUEST_NOT_FOUND": "Предложение уже обработано или недоступно.",
                "ALREADY_MARRIED": "Брак уже создан с участником.",
                "PLAYER_ACCESS_REQUIRED": "Действие доступно только участникам PRISMA.",
            }.get(error, "Не удалось обработать предложение.")
        else:
            text = {
                "RELATIONSHIP_REQUEST_NOT_FOUND": "Заявка уже обработана или недоступна.",
                "ALREADY_IN_RELATIONSHIP": "Отношения уже созданы с участником.",
                "PLAYER_ACCESS_REQUIRED": "Действие доступно только участникам PRISMA.",
            }.get(error, "Не удалось обработать заявку.")

        if callback.message:
            await callback.message.edit_reply_markup(reply_markup=None)
        await callback.answer(text, show_alert=True)
        return

    if callback.message:
        await callback.message.edit_reply_markup(reply_markup=None)
    await callback.answer(
        "Предложение принято." if kind == "MARRIAGE" and accept else
        "Предложение отклонено." if kind == "MARRIAGE" else
        "Заявка принята." if accept else
        "Заявка отклонена."
    )


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
