import logging
import re
import time
from datetime import datetime
from collections import defaultdict, deque
from html import escape

from aiogram import Bot, F, Router, types
from aiogram.exceptions import TelegramBadRequest

from config import MODERATION_GROUP_ID
from db.rpc import (
    bot_apply_automod_punishment,
    bot_get_automod_config,
    bot_record_automod_event,
    bot_rollback_automod_punishment,
    bot_set_community_membership,
)
from keyboards.inline import onboarding_group_keyboard
from services.community_membership import ensure_onboarding_restriction
from utils.chat_permissions import muted_chat_permissions

logger = logging.getLogger(__name__)
router = Router()

_cache = {"loaded_at": 0.0, "data": None}
_user_events = defaultdict(deque)
_user_repeats = defaultdict(deque)
_flood_inflight: set[tuple[int, int]] = set()
_flood_cooldowns: dict[tuple[int, int], float] = {}
_staff_cache: dict[tuple[int, int], tuple[float, bool]] = {}
_STAFF_CACHE_TTL = 30.0

LINK_RE = re.compile(r"(?:https?://|www\.|t\.me/|telegram\.me/)", re.I)

async def _config(chat_id: int):
    now = time.monotonic()
    if _cache["data"] is not None and now - _cache["loaded_at"] < 30:
        return _cache["data"]
    result = await bot_get_automod_config(chat_id)
    if result.error or not isinstance(result.data, dict):
        return {}
    _cache["data"] = result.data
    _cache["loaded_at"] = now
    return result.data

def _rule_from_config(data: dict, key: str):
    for rule in data.get("rules") or []:
        if str(rule.get("rule_key") or "") == key and rule.get("enabled", True):
            return rule
    return {}

async def _is_staff(message: types.Message) -> bool:
    if not message.from_user:
        return True

    key = (message.chat.id, message.from_user.id)
    now = time.monotonic()
    cached = _staff_cache.get(key)
    if cached and cached[0] > now:
        return cached[1]

    try:
        member = await message.bot.get_chat_member(message.chat.id, message.from_user.id)
    except Exception as exc:
        # Fail open when Telegram cannot confirm the sender's role. A transient
        # getChatMember error must never cause an administrator to be auto-muted.
        logger.warning(
            "Could not verify sender role; skipping automod for user %s: %s",
            message.from_user.id,
            exc,
        )
        return True

    is_staff = member.status in {"administrator", "creator"}
    _staff_cache[key] = (now + _STAFF_CACHE_TTL, is_staff)

    if len(_staff_cache) > 5000:
        current_time = time.monotonic()
        for cache_key, (expires_at, _) in list(_staff_cache.items()):
            if expires_at <= current_time:
                _staff_cache.pop(cache_key, None)

    return is_staff

def _text(message: types.Message) -> str:
    return (message.text or message.caption or "").strip()


def _effective_mute_until(result_data: dict) -> int | None:
    """
    Compose global and current-chat mutes into a single Telegram expiry.
    None means an active indefinite mute. For timed mutes, use the latest
    active expiry so a new flood mute cannot shorten an older punishment.
    """
    if result_data.get("has_indefinite_mute") or result_data.get("chat_has_indefinite_mute"):
        return None

    minimum_expiry = int(time.time()) + 30
    expiries: list[int] = []
    for field in ("expires_at", "muted_until", "chat_muted_until"):
        value = result_data.get(field)
        parsed: int | None = None
        if isinstance(value, str):
            try:
                parsed = int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
            except (TypeError, ValueError, OverflowError):
                parsed = None
        elif isinstance(value, (int, float)):
            parsed = int(value)

        if parsed is not None and parsed > minimum_expiry:
            expiries.append(parsed)

    if not expiries:
        raise ValueError("no safe future expiry in expires_at/muted_until/chat_muted_until")
    return max(expiries)


async def _touch_group_member(user: types.User):
    result = await bot_set_community_membership(
        user.id,
        user.username or "",
        user.first_name or "",
        user.last_name or "",
        user.full_name,
        True,
    )
    return result.data if isinstance(result.data, dict) else {}

async def _rollback_failed_mute(result_data: dict, error: Exception | str) -> None:
    punishment_id = result_data.get("punishment_id")
    if not punishment_id:
        logger.error("Automod mute could not be applied and no punishment ID was returned")
        return

    result = await bot_rollback_automod_punishment(str(punishment_id), str(error)[:1500])
    if result.error:
        logger.error(
            "Automod mute rollback failed for punishment %s: %s",
            punishment_id,
            result.error,
        )
        return

    data = result.data if isinstance(result.data, dict) else {}
    if data.get("success") is not True:
        logger.error(
            "Automod mute rollback returned an unexpected result for punishment %s: %r",
            punishment_id,
            data,
        )


async def _apply(
    message: types.Message,
    rule_key: str,
    action: str,
    score: float,
    reason: str,
    duration: int | None = None,
) -> bool:
    action = (action or "delete").lower()
    payload = {
        "message_id": message.message_id,
        "reason": reason,
        "text_preview": _text(message)[:200],
    }

    try:
        event_result = await bot_record_automod_event(
            message.chat.id,
            message.from_user.id if message.from_user else None,
            rule_key,
            action,
            score,
            payload,
        )
        if event_result.error:
            logger.warning("Could not persist automod event %s: %s", rule_key, event_result.error)
    except Exception:
        logger.exception("Could not persist automod event %s", rule_key)

    try:
        await message.delete()
    except Exception as exc:
        logger.debug("Could not delete automod message %s: %s", message.message_id, exc)

    result_data: dict = {}
    if action in {"warn", "mute", "ban"} and message.from_user:
        result = await bot_apply_automod_punishment(
            message.chat.id,
            message.from_user.id,
            action,
            reason,
            duration,
            rule_key,
            payload,
        )
        if result.error:
            logger.error(
                "Automod punishment failed: rule=%s action=%s user=%s error=%s",
                rule_key,
                action,
                message.from_user.id,
                result.error,
            )
            return False

        result_data = result.data if isinstance(result.data, dict) else {}
        if result_data.get("success") is not True or result_data.get("user_found") is False:
            logger.error(
                "Automod punishment was not recorded: rule=%s action=%s user=%s result=%r",
                rule_key,
                action,
                message.from_user.id,
                result_data,
            )
            return False

        expires_at = result_data.get("expires_at")
        until_date = None
        if isinstance(expires_at, str):
            try:
                until_date = int(datetime.fromisoformat(expires_at.replace("Z", "+00:00")).timestamp())
            except (TypeError, ValueError, OverflowError):
                until_date = None
        elif isinstance(expires_at, (int, float)):
            until_date = int(expires_at)

        if action == "mute":
            # Preserve the longest active mute across global and chat-only rows.
            # Otherwise a 2-hour flood mute could shorten an older global mute.
            has_indefinite_mute = bool(
                result_data.get("has_indefinite_mute")
                or result_data.get("chat_has_indefinite_mute")
            )
            try:
                until_date = _effective_mute_until(result_data)
            except ValueError as exc:
                logger.error(
                    "Automod mute has no safe effective expiry: rule=%s user=%s data=%r",
                    rule_key,
                    message.from_user.id,
                    {
                        "expires_at": result_data.get("expires_at"),
                        "muted_until": result_data.get("muted_until"),
                        "chat_muted_until": result_data.get("chat_muted_until"),
                    },
                )
                await _rollback_failed_mute(result_data, str(exc))
                return False

            try:
                applied = await message.bot.restrict_chat_member(
                    message.chat.id,
                    message.from_user.id,
                    permissions=muted_chat_permissions(),
                    until_date=until_date,
                    use_independent_chat_permissions=True,
                )
                if applied is False:
                    raise RuntimeError("Telegram returned false for restrictChatMember")
                logger.info(
                    "Automod mute applied: rule=%s user=%s telegram_until=%s indefinite=%s",
                    rule_key,
                    message.from_user.id,
                    until_date,
                    has_indefinite_mute,
                )
            except Exception as exc:
                logger.exception(
                    "Telegram failed to apply automod mute: rule=%s user=%s",
                    rule_key,
                    message.from_user.id,
                )
                await _rollback_failed_mute(result_data, exc)
                return False

        if action == "ban" or bool(result_data.get("auto_banned")):
            # Five-warning threshold is a permanent ban even though the triggering
            # warning itself expires after 30 days.
            ban_until_date = None if result_data.get("auto_banned") else until_date
            try:
                applied = await message.bot.ban_chat_member(
                    message.chat.id,
                    message.from_user.id,
                    until_date=ban_until_date,
                )
                if applied is False:
                    raise RuntimeError("Telegram returned false for banChatMember")
            except Exception:
                logger.exception(
                    "Telegram failed to apply automod ban: rule=%s user=%s",
                    rule_key,
                    message.from_user.id,
                )
                return False

    if action == "kick" and message.from_user:
        try:
            await message.bot.ban_chat_member(message.chat.id, message.from_user.id)
            await message.bot.unban_chat_member(message.chat.id, message.from_user.id, only_if_banned=True)
        except Exception:
            logger.exception("Automod kick failed for user %s", message.from_user.id)
            return False

    if action != "delete":
        label = {"warn": "⚠️ Предупреждение", "mute": "🔇 Мут", "ban": "⛔ Бан", "kick": "👢 Кик"}.get(action)
        if label:
            try:
                await message.bot.send_message(
                    message.chat.id,
                    f"{label}: <b>{escape(str(reason))}</b>",
                    parse_mode="HTML",
                    disable_notification=True,
                )
            except Exception as exc:
                logger.warning("Could not post automod notice for %s: %s", rule_key, exc)

    return True


@router.message(F.chat.type.in_({"group", "supergroup"}))
async def group_automod(message: types.Message):
    if message.chat.id != MODERATION_GROUP_ID:
        return
    if not message.from_user or message.from_user.is_bot:
        return

    # Capture receipt time before database/Telegram awaits; otherwise the flood
    # window measures handler latency rather than the pace of the user's messages.
    received_at = time.monotonic()
    await _touch_group_member(message.from_user)
    is_staff = await _is_staff(message)
    if is_staff:
        return

    data = await _config(message.chat.id)
    settings = data.get("settings") or {}
    text = _text(message)
    now = received_at
    key = (message.chat.id, message.from_user.id)

    if settings.get("anti_flood"):
        # Flood punishment is always a full 2-hour mute. The DB punishment
        # remains the source of truth; Telegram receives the same concrete expiry.
        # Updates are handled concurrently. De-duplicate messages already queued
        # while the first Telegram restriction is still being applied.
        cooldown_until = _flood_cooldowns.get(key, 0.0)
        if key in _flood_inflight or now < cooldown_until:
            try:
                await message.delete()
            except Exception:
                pass
            return

        rule = _rule_from_config(data, "flood")
        rule_config = rule.get("config") if isinstance(rule.get("config"), dict) else {}
        try:
            window = int(rule_config.get("window_seconds") or settings.get("flood_window_seconds") or 8)
        except (TypeError, ValueError):
            window = 8
        try:
            threshold = int(rule.get("threshold") or settings.get("flood_messages") or 5)
        except (TypeError, ValueError):
            threshold = 5
        window = max(1, min(window, 120))
        threshold = max(2, min(threshold, 100))

        q = _user_events[key]
        q.append(now)
        # Dispatcher tasks may resume out of order after awaits. Keep event times
        # ordered so old messages are not retained at the left edge by mistake.
        ordered_events = sorted(q)
        q.clear()
        q.extend(ordered_events)
        while len(q) > 1 and q[-1] - q[0] > window:
            q.popleft()

        if len(q) >= threshold:
            score = len(q)
            q.clear()
            action = str(rule.get("action") or settings.get("flood_action") or "mute").lower()
            if action not in {"off", "delete", "warn", "mute", "ban", "kick"}:
                action = "mute"

            # Flood mute is intentionally fixed at 2 hours. This prevents
            # a malformed/legacy rule duration from producing a tiny or indefinite mute.
            duration = 120 if action == "mute" else None
            if action == "ban":
                raw_duration = rule.get("duration_minutes")
                try:
                    duration = int(raw_duration) if raw_duration is not None else None
                except (TypeError, ValueError):
                    duration = None
                if duration is not None:
                    duration = max(1, min(duration, 10080))

            logger.info(
                "Flood detected: chat=%s user=%s messages=%s window_seconds=%s action=%s duration_minutes=%s",
                message.chat.id,
                message.from_user.id,
                score,
                window,
                action,
                duration,
            )
            _flood_inflight.add(key)
            try:
                applied = await _apply(message, "flood", action, score, "Флуд", duration)
                # A short cooldown absorbs the rest of the same burst. It is not
                # the punishment duration; Telegram enforces the actual mute.
                cooldown_seconds = max(5, min(window * 2, 30)) if applied else min(max(window, 3), 8)
                _flood_cooldowns[key] = time.monotonic() + cooldown_seconds
                if len(_flood_cooldowns) > 5000:
                    current_time = time.monotonic()
                    for cooldown_key, expires in list(_flood_cooldowns.items()):
                        if expires <= current_time:
                            _flood_cooldowns.pop(cooldown_key, None)
            except Exception:
                logger.exception("Flood automod handler failed for user %s", message.from_user.id)
                _flood_cooldowns[key] = time.monotonic() + min(max(window, 3), 8)
            finally:
                _flood_inflight.discard(key)
            return

    if text:
        if settings.get("anti_caps"):
            threshold = int(settings.get("caps_threshold") or 70)
            letters = [c for c in text if c.isalpha()]
            score = round(sum(1 for c in letters if c.isupper()) * 100 / len(letters)) if len(letters) >= 8 else 0
            if score >= threshold:
                await _apply(message, "caps", settings.get("caps_action") or "warn", score, "Слишком много заглавных букв")
                return

        if settings.get("anti_links") and LINK_RE.search(text):
            await _apply(message, "links", settings.get("links_action") or "warn", 1, "Ссылки запрещены")
            return

        repeat_q = _user_repeats[key]
        normalized = " ".join(text.lower().split())
        repeat_q.append((now, normalized))
        ordered_repeats = sorted(repeat_q, key=lambda item: item[0])
        repeat_q.clear()
        repeat_q.extend(ordered_repeats)
        latest_repeat_time = repeat_q[-1][0]
        while len(repeat_q) > 1 and latest_repeat_time - repeat_q[0][0] > 20:
            repeat_q.popleft()
        repeats = sum(1 for ts, value in repeat_q if value == normalized and normalized)
        if repeats >= 3:
            repeat_q.clear()
            await _apply(message, "repeat", settings.get("repeat_warn_action") or "mute", repeats, "Повторяющееся сообщение")
            return

        rule = _rule_from_config(data, "profanity")
        words = (rule.get("config") or {}).get("words") or []
        lowered = text.casefold()
        if settings.get("anti_profanity") and words and any(str(w).casefold() in lowered for w in words):
            await _apply(message, "profanity", settings.get("profanity_action") or "warn", 1, "Запрещённое слово")
            return

        if settings.get("anti_mentions") and text.count("@") >= 4:
            await _apply(message, "mentions", "warn", text.count("@"), "Слишком много упоминаний")
            return

    media = bool(message.photo or message.video or message.document or message.animation or message.sticker)
    if media and settings.get("anti_media") and (settings.get("media_action") or "off") != "off":
        await _apply(message, "media", settings.get("media_action") or "warn", 1, "Медиа запрещено")

@router.chat_member(F.chat.id == MODERATION_GROUP_ID)
async def community_membership(update: types.ChatMemberUpdated, bot: Bot):
    old_member = update.old_chat_member
    new_member = update.new_chat_member
    user = new_member.user
    if user.is_bot:
        return

    def is_active(member) -> bool:
        status = getattr(member, "status", "")
        if status in {"member", "administrator", "creator"}:
            return True
        if status == "restricted":
            return bool(getattr(member, "is_member", False))
        return False

    was_member = is_active(old_member)
    is_member = is_active(new_member)
    if was_member == is_member:
        return

    touch_result = await bot_set_community_membership(
        user.id,
        user.username or "",
        user.first_name or "",
        user.last_name or "",
        user.full_name,
        is_member,
    )
    if touch_result.error:
        logger.error("Failed to update community membership for %s: %s", user.id, touch_result.error)
        return
    touch = touch_result.data if isinstance(touch_result.data, dict) else {}

    name = escape(user.full_name)
    if is_member:
        # Apply/reconcile restrictions immediately for every join. The helper
        # checks actual application and moderation state from Supabase.
        try:
            await ensure_onboarding_restriction(bot, user.id, user.full_name)
        except Exception:
            logger.exception("Could not reconcile onboarding restriction for joining user %s", user.id)

        application_status = str(touch.get("application_status") or "").upper()
        if touch.get("bot_started"):
            text = (
                f"👋 <b>С возвращением, {name}!</b>\n\n"
                "Рады снова видеть вас в PRISMA."
            )
            markup = None
        elif application_status in {"PENDING", "ACCEPTED"}:
            text = (
                f"👋 <b>С возвращением, {name}!</b>\n\n"
                "У вас уже есть заявка PRISMA. Повторно подавать её не нужно."
            )
            markup = None
        else:
            text = (
                f"👋 <b>Добро пожаловать, {name}!</b>\n\n"
                "Чтобы получить доступ к серверу PRISMA, откройте бота и подайте заявку."
            )
            markup = onboarding_group_keyboard()
        try:
            await update.bot.send_message(
                update.chat.id,
                text,
                reply_markup=markup,
                parse_mode="HTML",
                disable_notification=True,
            )
        except Exception as exc:
            logger.warning("Could not send group welcome message: %s", exc)
        return

    try:
        await update.bot.send_message(
            update.chat.id,
            f"👋 <b>{name}</b> покинул(а) группу. До встречи!",
            parse_mode="HTML",
            disable_notification=True,
        )
    except Exception as exc:
        logger.warning("Could not send group leave message: %s", exc)


@router.message(F.chat.id == MODERATION_GROUP_ID, F.new_chat_members)
async def join_guard(message: types.Message):
    data = await _config(message.chat.id)
    settings = data.get("settings") or {}
    if not settings.get("anti_raid"):
        return
    for user in message.new_chat_members or []:
        if user.is_bot:
            continue
        try:
            await message.bot.restrict_chat_member(
                message.chat.id,
                user.id,
                permissions=types.ChatPermissions(can_send_messages=False),
            )
        except Exception:
            pass
