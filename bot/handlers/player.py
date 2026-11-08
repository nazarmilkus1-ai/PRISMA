from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, StateFilter
from aiogram.fsm.context import FSMContext

from db.player import (
    _user,
    create_appeal,
    get_achievements,
    get_notification_preferences,
    get_online_players,
    get_own_punishments,
    get_player_appeals,
    get_player_reports,
    get_server_metrics,
    get_stats,
    leaderboard,
    list_battles,
    list_events,
    register_event,
    start_battle,
    unregister_event,
    set_notification_preference,
)
from db.rpc import call_rpc_async
from fsm.states import AppealForm
from keyboards.inline import (
    appeal_keyboard,
    event_keyboard,
    main_menu_approved,
    notification_keyboard,
    player_center_keyboard,
)
from config import (
    MINECRAFT_BEDROCK_ADDRESS,
    MINECRAFT_BEDROCK_PORT,
    MINECRAFT_HOST,
    MINECRAFT_JAVA_ADDRESS,
    MINECRAFT_JAVA_PORT,
    SITE_URL,
)
from utils.mode import ADMIN_MODE
from utils.permissions import ensure_mode, has_any_staff_permission, is_approved

router = Router()


async def main_menu_approved_for_user(tg_id: int):
    mode = await ensure_mode(tg_id)
    return main_menu_approved(
        show_admin_switch=mode != ADMIN_MODE and await has_any_staff_permission(tg_id)
    )


def _duration(minutes):
    if minutes is None:
        return "бессрочно"
    minutes = int(minutes)
    if minutes < 60:
        return f"{minutes} мин."
    hours, rest = divmod(minutes, 60)
    return f"{hours} ч." if rest == 0 else f"{hours} ч. {rest} мин."


async def _center_text(tg_id: int):
    user, err = await _user(tg_id)
    if err or not user:
        return None
    role_result = await call_rpc_async("mc_get_staff_identity", {"p_user_id": str(user.get("id"))})
    role = "Участник"
    if not role_result.error and isinstance(role_result.data, dict):
        role_names = {
            "helper": "Хелпер",
            "moderator": "Модератор",
            "admin": "Администратор",
            "head_admin": "Главный администратор",
            "owner": "Владелец",
            "content_maker": "Контент-мейкер",
            "participant": "Участник",
        }
        role = role_names.get(str(role_result.data.get("role") or "participant"), "Участник")

    return (
        "👤 <b>Мой PRISMA</b>\n\n"
        f"Telegram: @{escape(str(user.get('telegram_username') or '—').lstrip('@'))}\n"
        f"Minecraft: <code>{escape(str(user.get('minecraft_nickname') or '—'))}</code>\n"
        f"Привилегия: <b>{escape(role)}</b>\n"
        f"Уровень: <b>{user.get('level', 1)}</b>  •  XP: <b>{user.get('xp', 0)}</b>\n"
        f"Рейтинг: <b>{user.get('rating', 0)}</b>  •  Активность: <b>{user.get('activity_score', 0)}</b>\n"
        f"Whitelist: {'✅' if user.get('is_whitelisted') else '❌'}"
    )


async def show_center_message(message: types.Message, tg_id: int, edit: bool = False):
    if not await is_approved(tg_id):
        await message.answer("⏳ Центр игрока доступен после одобрения заявки.")
        return
    text = await _center_text(tg_id)
    if not text:
        await message.answer("❌ Не удалось загрузить профиль.")
        return
    if edit:
        await message.edit_text(text, reply_markup=player_center_keyboard(), parse_mode="HTML")
    else:
        await message.answer(text, reply_markup=player_center_keyboard(), parse_mode="HTML")


@router.callback_query(F.data == "profile")
async def profile_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Центр игрока доступен после одобрения заявки.", show_alert=True)
        return
    await callback.answer()
    if callback.message:
        await show_center_message(callback.message, callback.from_user.id, edit=True)


@router.message(Command("me"))
async def me_command(message: types.Message):
    await show_center_message(message, message.from_user.id)


async def _stats_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Статистика доступна после одобрения заявки.")
        return
    user, err = await _user(tg_id)
    stats, stats_err = await get_stats(tg_id)
    if not user or stats_err:
        await message.answer("❌ Не удалось загрузить статистику.")
        return
    playtime = int(stats.get("playtime_minutes", 0))
    await message.answer(
        "📊 <b>Статистика</b>\n\n"
        f"Уровень / XP: <b>{user.get('level', 1)} / {user.get('xp', 0)}</b>\n"
        f"Рейтинг: <b>{user.get('rating', 0)}</b>\n"
        f"Активность: <b>{user.get('activity_score', 0)}</b>\n"
        f"Убийства / смерти: <b>{stats.get('kills', 0)} / {stats.get('deaths', 0)}</b>\n"
        f"K/D: <b>{(int(stats.get('kills', 0)) / int(stats.get('deaths', 0)) if int(stats.get('deaths', 0)) else int(stats.get('kills', 0))):.2f}</b>\n"
        f"Блоки: <b>+{stats.get('blocks_placed', 0)} / -{stats.get('blocks_broken', 0)}</b>\n"
        f"Мобы: <b>{stats.get('mobs_killed', 0)}</b>\n"
        f"Дистанция: <b>{stats.get('distance_walked', 0)} м</b>\n"
        f"Урон: <b>{stats.get('damage_dealt', 0)} / {stats.get('damage_taken', 0)}</b>\n"
        f"Игровое время: <b>{playtime // 60} ч. {playtime % 60} мин.</b>\n"
        f"Входы / выходы: <b>{stats.get('joins', 0)} / {stats.get('quits', 0)}</b>\n"
        f"Сообщения: <b>{stats.get('chat', 0)}</b>\n"
        f"Команды: <b>{stats.get('commands', 0)}</b>",
        parse_mode="HTML",
        reply_markup=await main_menu_approved_for_user(tg_id),
    )


@router.message(Command("stats"))
async def stats_command(message: types.Message):
    await _stats_message(message, message.from_user.id)


@router.callback_query(F.data == "player:stats")
async def stats_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _stats_message(callback.message, callback.from_user.id)


async def _achievements_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Достижения доступны после одобрения заявки.")
        return
    user, _ = await _user(tg_id)
    rows, err = await get_achievements(tg_id) if user else ([], "USER_NOT_FOUND")
    if err or not rows:
        await message.answer("🏆 <b>Достижения</b>\n\nПока нет открытых достижений.", parse_mode="HTML")
        return
    chunks = ["🏆 <b>Достижения</b>"]
    for row in rows[:20]:
        chunks.append(
            f"\n{row.get('icon') or '🏆'} <b>{escape(str(row.get('title') or row.get('code') or 'Достижение'))}</b>"
            f"\n{escape(str(row.get('description') or ''))}"
        )
    await message.answer("\n".join(chunks), parse_mode="HTML")


@router.message(Command("achievements"))
async def achievements_command(message: types.Message):
    await _achievements_message(message, message.from_user.id)


@router.callback_query(F.data == "player:achievements")
async def achievements_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _achievements_message(callback.message, callback.from_user.id)


async def _punishments_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Эта функция доступна после одобрения заявки.")
        return
    user, err = await _user(tg_id)
    rows, db_err = await get_own_punishments(tg_id) if user else ([], err)
    active = [r for r in rows if str(r.get("status") or "").upper() == "ACTIVE"]
    if db_err:
        await message.answer("❌ Не удалось загрузить наказания.")
        return
    if not active:
        await message.answer("⚖️ <b>Наказания</b>\n\nАктивных наказаний нет.", parse_mode="HTML")
        return
    chunks = ["⚖️ <b>Ваши активные наказания</b>"]
    for row in active[:10]:
        expires = row.get("expires_at")
        suffix = f"\nДо: <code>{escape(str(expires))}</code>" if expires else ""
        chunks.append(
            f"\n<b>{escape(str(row.get('type') or '—'))}</b>: "
            f"{escape(str(row.get('reason') or '—'))}\n"
            f"Срок: {escape(_duration(row.get('duration_minutes')))}{suffix}"
        )
    await message.answer("\n".join(chunks), parse_mode="HTML")
    for row in active[:5]:
        if row.get("id"):
            await message.answer(
                f"⚖️ Апелляция по наказанию <b>{escape(str(row.get('type') or ''))}</b>",
                reply_markup=appeal_keyboard(str(row["id"])),
                parse_mode="HTML",
            )


@router.message(Command("warnings"))
async def warnings_command(message: types.Message):
    await _punishments_message(message, message.from_user.id)


@router.callback_query(F.data == "player:punishments")
async def punishments_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _punishments_message(callback.message, callback.from_user.id)


def _minecraft_address(address: str, port: int) -> str:
    value = (address or "").strip()
    if value:
        return value
    if MINECRAFT_HOST:
        return f"{MINECRAFT_HOST}:{port}"
    return f"IP не настроен · порт {port}"


async def _server_message(message: types.Message):
    metrics, metrics_err = await get_server_metrics()
    players, players_err = await get_online_players()
    r = await call_rpc_async("bot_get_server_status", {})
    status = None
    if not r.error and isinstance(r.data, dict):
        status = r.data.get("status")

    if metrics_err and not status:
        await message.answer("❌ Статус сервера сейчас недоступен.")
        return

    metrics = metrics or {}
    player_names = [
        str(row.get("minecraft_nickname") or "").strip()
        for row in (players or [])
        if isinstance(row, dict) and str(row.get("minecraft_nickname") or "").strip()
    ][:50]

    online_count = len(player_names) if not players_err else int(metrics.get("online_players") or 0)
    online_text = "\n".join(
        f"• <code>{escape(name)}</code>" for name in player_names
    ) if player_names else "• Никого нет онлайн."

    java_address = _minecraft_address(MINECRAFT_JAVA_ADDRESS, MINECRAFT_JAVA_PORT)
    bedrock_address = _minecraft_address(MINECRAFT_BEDROCK_ADDRESS, MINECRAFT_BEDROCK_PORT)

    response = (
        "🖥 <b>PRISMA SERVER</b>\n\n"
        f"Состояние: <b>{escape(str(status or 'unknown').upper())}</b>\n"
        f"Онлайн: <b>{online_count}/{metrics.get('max_players', '—')}</b>\n"
        f"Версия: <b>{escape(str(metrics.get('version') or '—'))}</b>\n\n"
        "<b>☕ Java</b>\n"
        f"<code>{escape(java_address)}</code>\n\n"
        "<b>🧱 Bedrock</b>\n"
        f"<code>{escape(bedrock_address)}</code>\n\n"
        "<b>👥 Сейчас играют</b>\n"
        f"{online_text}"
    )
    if players_err:
        response += "\n\n⚠️ Список игроков временно недоступен."

    await message.answer(response, parse_mode="HTML")


@router.message(Command("wiki"))
async def wiki_command(message: types.Message):
    await message.answer(
        "📖 <b>Wiki PRISMA</b>\n\n"
        "Официальная Wiki проекта: знания о PRISMA, Minecraft, системах и Staff.",
        reply_markup=types.InlineKeyboardMarkup(
            inline_keyboard=[
                [types.InlineKeyboardButton(text="📚 Открыть Wiki", url=f"{SITE_URL}/wiki")]
            ]
        ),
        parse_mode="HTML",
    )


@router.message(Command("server"))
async def server_command(message: types.Message):
    await _server_message(message)


@router.callback_query(F.data == "player:server")
async def server_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _server_message(callback.message)


async def _battles_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Player Battle доступен после одобрения заявки.")
        return

    rows, err = await list_battles(tg_id, 10)
    if err:
        await message.answer("❌ Не удалось загрузить историю Player Battle.")
        return

    if not rows:
        await message.answer(
            "⚔️ <b>Player Battle</b>\n\n"
            "Батлов пока нет.\n"
            "Запусти первый: <code>/battle MinecraftNick</code>",
            parse_mode="HTML",
        )
        return

    chunks = ["⚔️ <b>Мои последние Player Battle</b>"]
    for row in rows:
        challenger = escape(str(row.get("challenger_nickname") or "Игрок"))
        opponent = escape(str(row.get("opponent_nickname") or "Игрок"))
        score = f"{row.get('challenger_score', 0)} : {row.get('opponent_score', 0)}"
        result = {
            "WIN": "Победа",
            "LOSS": "Поражение",
            "DRAW": "Ничья",
        }.get(str(row.get("viewer_result") or "DRAW"), "Ничья")
        delta = int(row.get("viewer_delta") or 0)
        if delta:
            result += f" · {'+' if delta > 0 else ''}{delta} рейтинга"
        chunks.append(f"\n<b>{challenger} vs {opponent}</b> · <code>{score}</code>\n{escape(result)}")

    await message.answer("\n".join(chunks), parse_mode="HTML")


@router.callback_query(F.data == "player:battles")
async def battles_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Player Battle доступен после одобрения заявки.", show_alert=True)
        return
    await callback.answer()
    if callback.message:
        await _battles_message(callback.message, callback.from_user.id)


@router.message(Command("battle"))
async def battle_command(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer("⏳ Player Battle доступен после одобрения заявки.")
        return

    parts = (message.text or "").split(maxsplit=1)
    if len(parts) != 2 or not parts[1].strip():
        await message.answer(
            "⚔️ Использование: <code>/battle MinecraftNick</code>",
            parse_mode="HTML",
        )
        return

    result, err = await start_battle(message.from_user.id, parts[1].strip())
    if err:
        errors = {
            "USER_NOT_FOUND": "Профиль PRISMA не найден.",
            "PLAYER_ACCESS_REQUIRED": "Player Battle доступен только одобренным участникам с whitelist.",
            "OPPONENT_INVALID": "Укажите корректный Minecraft-ник.",
            "OPPONENT_NOT_FOUND": "Игрок не найден или не может участвовать в бою.",
            "BATTLE_COOLDOWN": "С этим игроком уже был бой в последние 24 часа.",
        }
        await message.answer(f"❌ {errors.get(str(err), 'Не удалось провести Player Battle.')}")
        return

    winner_id = result.get("winner_id")
    if not winner_id:
        verdict = "Ничья. Рейтинг не изменился."
    elif winner_id and result.get("challenger_score", 0) > result.get("opponent_score", 0):
        verdict = f"Победа! <b>+{result.get('points_awarded', 0)}</b> рейтинга."
    else:
        verdict = f"Поражение. <b>-{result.get('points_awarded', 0)}</b> рейтинга."

    await message.answer(
        "⚔️ <b>Player Battle завершён</b>\n\n"
        f"Счёт: <b>{result.get('challenger_score', 0)} : {result.get('opponent_score', 0)}</b>\n"
        f"{verdict}\n"
        f"Ваш рейтинг: <b>{result.get('viewer_rating', result.get('challenger_rating', 0))}</b>",
        parse_mode="HTML",
    )


@router.message(Command("battles"))
async def battles_command(message: types.Message):
    await _battles_message(message, message.from_user.id)


async def _events_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Ивенты доступны после одобрения заявки.")
        return
    rows, err = await list_events(tg_id)
    if err:
        await message.answer("❌ Не удалось загрузить ивенты.")
        return
    if not rows:
        await message.answer("🎯 <b>Ивенты</b>\n\nСейчас активных ивентов нет.", parse_mode="HTML")
        return
    for event in rows[:10]:
        text = (
            f"🎯 <b>{escape(str(event.get('title') or event.get('slug') or 'Ивент'))}</b>\n"
            f"{escape(str(event.get('description') or ''))}\n\n"
            f"Начало: <code>{escape(str(event.get('starts_at') or 'уточняется'))}</code>"
        )
        await message.answer(text, reply_markup=event_keyboard(str(event["id"]), bool(event.get("registered"))), parse_mode="HTML")


@router.message(Command("events"))
async def events_command(message: types.Message):
    await _events_message(message, message.from_user.id)


@router.callback_query(F.data == "player:events")
async def events_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _events_message(callback.message, callback.from_user.id)


@router.callback_query(F.data.startswith("event:reg:"))
async def event_register_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Доступно после одобрения заявки.", show_alert=True)
        return
    event_id = callback.data.split(":", 2)[2]
    ok, result = await register_event(callback.from_user.id, event_id)
    if ok:
        await callback.answer("✅ Вы зарегистрированы на ивент.")
        if callback.message:
            await _events_message(callback.message, callback.from_user.id)
        return
    errors = {
        "ALREADY_REGISTERED": "Вы уже зарегистрированы.",
        "REGISTRATION_CLOSED": "Регистрация уже закрыта.",
        "EVENT_FULL": "Свободных мест больше нет.",
        "EVENT_NOT_FOUND": "Ивент не найден.",
    }
    await callback.answer(errors.get(str(result), "Не удалось зарегистрироваться."), show_alert=True)


@router.callback_query(F.data.startswith("event:unreg:"))
async def event_unregister_callback(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Доступно после одобрения заявки.", show_alert=True)
        return
    event_id = callback.data.split(":", 2)[2]
    ok, result = await unregister_event(callback.from_user.id, event_id)
    if ok:
        await callback.answer("✅ Регистрация отменена.")
        if callback.message:
            await _events_message(callback.message, callback.from_user.id)
        return
    errors = {
        "EVENT_ALREADY_STARTED": "Отменить регистрацию после начала события нельзя.",
        "REGISTRATION_CLOSED": "Регистрация уже закрыта.",
        "REGISTRATION_NOT_FOUND": "Вы не зарегистрированы на это событие.",
        "EVENT_NOT_FOUND": "Событие не найдено.",
    }
    await callback.answer(errors.get(str(result), "Не удалось отменить регистрацию."), show_alert=True)


async def _notifications_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Настройки уведомлений доступны после одобрения заявки.")
        return
    user, err = await _user(tg_id)
    prefs, pref_err = await get_notification_preferences(tg_id) if user else ({}, err)
    if pref_err:
        await message.answer("❌ Не удалось загрузить настройки уведомлений.")
        return
    await message.answer(
        "🔔 <b>Уведомления PRISMA</b>\n\nНажмите на категорию, чтобы переключить её.",
        reply_markup=notification_keyboard(prefs or {}),
        parse_mode="HTML",
    )


@router.message(Command("notifications"))
async def notifications_command(message: types.Message):
    await _notifications_message(message, message.from_user.id)


@router.callback_query(F.data == "player:notifications")
async def notifications_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _notifications_message(callback.message, callback.from_user.id)


@router.callback_query(F.data.startswith("notify:"))
async def notification_toggle(callback: types.CallbackQuery):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Недоступно до одобрения заявки.", show_alert=True)
        return
    key = callback.data.split(":", 1)[1]
    user, err = await _user(callback.from_user.id)
    prefs, pref_err = await get_notification_preferences(callback.from_user.id) if user else ({}, err)
    if pref_err:
        await callback.answer("❌ Не удалось прочитать настройки.", show_alert=True)
        return
    enabled = not bool((prefs or {}).get(key, True))
    ok, _ = await set_notification_preference(callback.from_user.id, key, enabled)
    if not ok:
        await callback.answer("❌ Не удалось сохранить настройку.", show_alert=True)
        return
    prefs[key] = enabled
    if callback.message:
        await callback.message.edit_reply_markup(reply_markup=notification_keyboard(prefs))
    await callback.answer("Включено." if enabled else "Отключено.")


async def _reports_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Репорты доступны после одобрения заявки.")
        return
    rows, err = await get_player_reports(tg_id)
    if err:
        await message.answer("❌ Не удалось загрузить ваши репорты.")
        return
    if not rows:
        await message.answer("📋 <b>Мои жалобы</b>\n\nВы ещё не создавали жалоб.", parse_mode="HTML")
        return
    chunks = ["📋 <b>Мои жалобы</b>"]
    for row in rows[:15]:
        chunks.append(
            f"\n<b>#{escape(str(row.get('ticket_no') or row.get('id')))}</b> · "
            f"{escape(str(row.get('status') or 'OPEN'))}\n"
            f"На: <code>{escape(str(row.get('target_nickname') or '—'))}</code>\n"
            f"{escape(str(row.get('description') or ''))}"
        )
    await message.answer("\n".join(chunks), parse_mode="HTML")


@router.message(Command("my_reports"))
async def my_reports(message: types.Message):
    await _reports_message(message, message.from_user.id)


@router.callback_query(F.data == "player:reports")
async def reports_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _reports_message(callback.message, callback.from_user.id)


async def _leaderboard_message(message: types.Message, tg_id: int):
    if not await is_approved(tg_id):
        await message.answer("⏳ Топ игроков доступен после одобрения заявки.")
        return
    rows, err = await leaderboard("rating", 10)
    if err:
        await message.answer("❌ Не удалось загрузить рейтинг.")
        return
    chunks = ["🏅 <b>Топ игроков по рейтингу</b>"]
    for index, row in enumerate(rows, 1):
        nick = row.get("minecraft_nickname") or row.get("telegram_username") or "Игрок"
        chunks.append(f"{index}. <b>{escape(str(nick))}</b> — {row.get('rating', 0)}")
    await message.answer("\n".join(chunks), parse_mode="HTML")


@router.message(Command("top"))
async def top_command(message: types.Message):
    await _leaderboard_message(message, message.from_user.id)


@router.callback_query(F.data == "player:top")
async def top_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await _leaderboard_message(callback.message, callback.from_user.id)


@router.message(Command("appeal"))
async def appeal_command(message: types.Message, state: FSMContext):
    if not await is_approved(message.from_user.id):
        await message.answer("⏳ Апелляции доступны после одобрения заявки.")
        return
    args = (message.text or "").split(maxsplit=1)
    punishment_id = args[1].strip() if len(args) == 2 else None
    if not punishment_id:
        user, _ = await _user(message.from_user.id)
        rows, _ = await get_own_punishments(user["id"]) if user else ([], None)
        active = [r for r in rows if str(r.get("status") or "").upper() == "ACTIVE"]
        if not active:
            await message.answer("⚖️ Нет активного наказания, для которого можно подать апелляцию.")
            return
        punishment_id = active[0].get("id")
    await state.update_data(punishment_id=punishment_id)
    await state.set_state(AppealForm.waiting_reason)
    await message.answer("⚖️ Опишите причину апелляции (10–2000 символов) или /cancel.")


@router.callback_query(F.data.startswith("appeal:"))
async def appeal_callback(callback: types.CallbackQuery, state: FSMContext):
    if not await is_approved(callback.from_user.id):
        await callback.answer("⏳ Недоступно до одобрения заявки.", show_alert=True)
        return
    await callback.answer()
    await state.update_data(punishment_id=callback.data.split(":", 1)[1])
    await state.set_state(AppealForm.waiting_reason)
    if callback.message:
        await callback.message.answer("⚖️ Опишите причину апелляции (10–2000 символов) или /cancel.")


@router.message(StateFilter(AppealForm.waiting_reason))
async def appeal_reason(message: types.Message, state: FSMContext):
    reason = (message.text or "").strip()
    if not 10 <= len(reason) <= 2000:
        await message.answer("❌ Причина должна содержать 10–2000 символов.")
        return
    data = await state.get_data()
    row, err = await create_appeal(message.from_user.id, reason, data.get("punishment_id"))
    if err or not row:
        messages = {
            "PUNISHMENT_NOT_FOUND": "❌ Наказание не найдено или оно принадлежит другому игроку.",
            "PUNISHMENT_NOT_ACTIVE": "⏳ Это наказание уже неактивно.",
            "NO_ACTIVE_PUNISHMENT": "⚖️ Активных наказаний для апелляции нет.",
            "APPEAL_ALREADY_EXISTS": "⚠️ По этому наказанию у вас уже есть открытая апелляция.",
            "INVALID_REASON": "❌ Причина должна содержать 10–2000 символов.",
        }
        await message.answer(messages.get(str(err), "❌ Не удалось создать апелляцию."))
        return
    await state.clear()
    await message.answer("✅ Апелляция отправлена администрации. Статус: OPEN.")


@router.message(Command("my_appeals"))
async def my_appeals(message: types.Message):
    if not await is_approved(message.from_user.id):
        await message.answer("⏳ Апелляции доступны после одобрения заявки.")
        return
    rows, err = await get_player_appeals(message.from_user.id)
    if err:
        await message.answer("❌ Не удалось загрузить апелляции.")
        return
    if not rows:
        await message.answer("📝 Апелляций пока нет.")
        return
    chunks = ["📝 <b>Мои апелляции</b>"]
    for row in rows:
        chunks.append(
            f"\n<b>{escape(str(row.get('status') or '—'))}</b> · "
            f"<code>{escape(str(row.get('created_at') or ''))}</code>\n"
            f"{escape(str(row.get('reason') or ''))}"
        )
    await message.answer("\n".join(chunks), parse_mode="HTML")


@router.callback_query(F.data == "player:appeals")
async def appeals_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await my_appeals(callback.message)


@router.callback_query(F.data == "player:clan")
async def clan_callback(callback: types.CallbackQuery):
    await callback.answer()
    if callback.message:
        await callback.message.answer("⚔️ Кланы: /clan", reply_markup=await main_menu_approved_for_user(callback.from_user.id))
