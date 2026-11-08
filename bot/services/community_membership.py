import asyncio
import logging

from aiogram import Bot, types
from aiogram.exceptions import TelegramBadRequest, TelegramForbiddenError

from config import MODERATION_GROUP_ID
from db.rpc import (
    bot_get_user_status,
    bot_list_community_membership_candidates,
    bot_list_onboarding_restriction_candidates,
    bot_set_community_membership,
    bot_set_onboarding_restriction_state,
)

logger = logging.getLogger(__name__)

RECONCILE_INTERVAL_SECONDS = 300
MAX_CONCURRENCY = 4

ONBOARDING_NOTICE = (
    "🚫 <b>Ограничение PRISMA</b>\n\n"
    "У вас пока нет заявки в PRISMA. Поэтому в группе временно отключены "
    "стикеры, GIF и медиа. Обычные текстовые сообщения доступны.\n\n"
    "Чтобы снять ограничение, откройте бота PRISMA и подайте заявку. "
    "После отправки заявки ограничение снимается автоматически."
)


def _is_active_member(member) -> bool:
    status = getattr(member, "status", "")
    if status in {"member", "administrator", "creator"}:
        return True
    if status == "restricted":
        return bool(getattr(member, "is_member", False))
    return False


def _is_admin(member) -> bool:
    return getattr(member, "status", "") in {"administrator", "creator"}


def _is_missing_member_error(exc: Exception) -> bool:
    text = str(exc).casefold()
    return any(
        marker in text
        for marker in (
            "user not found",
            "member not found",
            "participant_id_invalid",
            "chat member not found",
            "user is not a member",
        )
    )


def _text_only_permissions() -> types.ChatPermissions:
    return types.ChatPermissions(
        can_send_messages=True,
        can_send_audios=False,
        can_send_documents=False,
        can_send_photos=False,
        can_send_videos=False,
        can_send_video_notes=False,
        can_send_voice_notes=False,
        can_send_polls=False,
        can_send_other_messages=False,
        can_add_web_page_previews=False,
    )


def _full_member_permissions() -> types.ChatPermissions:
    return types.ChatPermissions(
        can_send_messages=True,
        can_send_audios=True,
        can_send_documents=True,
        can_send_photos=True,
        can_send_videos=True,
        can_send_video_notes=True,
        can_send_voice_notes=True,
        can_send_polls=True,
        can_send_other_messages=True,
        can_add_web_page_previews=True,
    )


async def _telegram_member(bot: Bot, tg_id: int):
    try:
        return await bot.get_chat_member(MODERATION_GROUP_ID, tg_id)
    except TelegramBadRequest as exc:
        if _is_missing_member_error(exc):
            return None
        raise


async def _load_onboarding_row(tg_id: int) -> dict | None:
    result = await bot_list_onboarding_restriction_candidates()
    if result.error or not isinstance(result.data, list):
        return None
    for row in result.data:
        if isinstance(row, dict) and int(row.get("tg_id") or 0) == tg_id:
            return row
    return None


async def ensure_onboarding_restriction(
    bot: Bot,
    tg_id: int,
    display_name: str | None = None,
    row: dict | None = None,
) -> bool:
    if not MODERATION_GROUP_ID:
        return False

    row = row or await _load_onboarding_row(tg_id)
    if not row:
        return False

    # Keep moderation punishments authoritative: onboarding cleanup must never
    # restore permissions while a ban or mute is active.
    if row.get("is_banned") or row.get("is_muted"):
        return False

    if bool(row.get("has_application")):
        if row.get("onboarding_restricted"):
            return await clear_onboarding_restriction(bot, tg_id, row=row)
        return False

    try:
        member = await _telegram_member(bot, tg_id)
    except TelegramForbiddenError:
        logger.error("Onboarding restriction lost Telegram access")
        return False
    except Exception as exc:
        logger.warning("Onboarding membership lookup failed for %s: %s", tg_id, exc)
        return False

    if member is None or not _is_active_member(member) or _is_admin(member) or row.get("is_banned") or row.get("is_muted"):
        return False

    # Re-apply permissions even when the DB flag is already true. The flag is
    # only our last-known state; an admin or another bot action may have reset
    # Telegram permissions since the previous reconciliation.
    was_marked_restricted = bool(row.get("onboarding_restricted"))
    try:
        await bot.restrict_chat_member(
            MODERATION_GROUP_ID,
            tg_id,
            permissions=_text_only_permissions(),
            use_independent_chat_permissions=True,
        )
        state = await bot_set_onboarding_restriction_state(tg_id, True, False)
        if state.error:
            logger.error("Failed to save onboarding restriction state for %s: %s", tg_id, state.error)
        if not was_marked_restricted:
            logger.info("Onboarding text-only restriction applied to %s", tg_id)
        else:
            logger.debug("Onboarding text-only restriction reasserted for %s", tg_id)
    except Exception as exc:
        logger.warning("Failed to restrict onboarding user %s: %s", tg_id, exc)
        return False

    if not row.get("onboarding_restriction_notified_at"):
        name = display_name or row.get("full_name") or row.get("username") or "участник"
        safe_name = str(name).replace("<", "&lt;").replace(">", "&gt;")
        try:
            notice = (
                f"🚫 <b>Ограничение PRISMA</b>\n\n"
                f"<a href=\"tg://user?id={tg_id}\">{safe_name}</a>, у вас пока нет заявки в PRISMA. "
                f"Поэтому в группе временно отключены стикеры, GIF и медиа. "
                f"Обычные текстовые сообщения доступны.\n\n"
                f"Чтобы снять ограничение, откройте бота PRISMA и подайте заявку. "
                f"После отправки заявки ограничение снимается автоматически."
            )
            await bot.send_message(
                MODERATION_GROUP_ID,
                notice,
                parse_mode="HTML",
                disable_notification=True,
            )
            await bot_set_onboarding_restriction_state(tg_id, True, True)
        except Exception as exc:
            logger.warning("Failed to send onboarding restriction notice for %s: %s", tg_id, exc)
    return True




async def clear_onboarding_restriction(
    bot: Bot,
    tg_id: int,
    row: dict | None = None,
) -> bool:
    # This helper is also called immediately after application submission.
    # Verify current moderation flags before restoring Telegram permissions,
    # otherwise submitting an application could accidentally lift a mute.
    row = row or await _load_onboarding_row(tg_id)
    if not row:
        logger.warning("Could not verify onboarding state for %s; leaving permissions unchanged", tg_id)
        return False
    if not row.get("has_application"):
        return False
    if row.get("is_banned") or row.get("is_muted"):
        logger.info("Not clearing onboarding restriction for %s while moderation is active", tg_id)
        return False

    try:
        member = await _telegram_member(bot, tg_id)
        if member is None or not _is_active_member(member) or _is_admin(member):
            return False
        await bot.restrict_chat_member(
            MODERATION_GROUP_ID,
            tg_id,
            permissions=_full_member_permissions(),
            use_independent_chat_permissions=True,
        )
        state = await bot_set_onboarding_restriction_state(tg_id, False, False)
        if state.error:
            logger.error("Failed to save onboarding restriction removal for %s: %s", tg_id, state.error)
            return False
        return True
    except Exception as exc:
        logger.warning("Failed to remove onboarding restriction for %s: %s", tg_id, exc)
        return False

async def reconcile_onboarding_restrictions(bot: Bot) -> int:
    if not MODERATION_GROUP_ID:
        return 0

    result = await bot_list_onboarding_restriction_candidates()
    if result.error or not isinstance(result.data, list):
        logger.error("Onboarding restriction candidate query failed: %s", result.error)
        return 0

    candidates = [row for row in result.data if isinstance(row, dict) and row.get("tg_id")]
    semaphore = asyncio.Semaphore(MAX_CONCURRENCY)
    changed = 0

    async def check(row: dict) -> int:
        tg_id = int(row["tg_id"])
        has_application = bool(row.get("has_application"))
        try:
            async with semaphore:
                member = await _telegram_member(bot, tg_id)
            if member is None:
                if not row.get("onboarding_restricted"):
                    logger.info("Skipping onboarding restriction for %s: Telegram says user is not in the group", tg_id)
                return 0
            if not _is_active_member(member):
                if not row.get("onboarding_restricted"):
                    logger.info("Skipping onboarding restriction for %s: Telegram membership is not active", tg_id)
                return 0
            if _is_admin(member):
                if not row.get("onboarding_restricted"):
                    logger.info("Skipping onboarding restriction for %s: Telegram user is an administrator/creator", tg_id)
                return 0
            if row.get("is_banned") or row.get("is_muted"):
                if not row.get("onboarding_restricted"):
                    logger.info("Skipping onboarding restriction for %s: an active ban/mute takes precedence", tg_id)
                return 0

            if not has_application:
                before = bool(row.get("onboarding_restricted"))
                await ensure_onboarding_restriction(
                    bot,
                    tg_id,
                    row.get("full_name") or row.get("username"),
                    row=row,
                )
                return 1 if not before else 0

            if row.get("onboarding_restricted"):
                async with semaphore:
                    await bot.restrict_chat_member(
                        MODERATION_GROUP_ID,
                        tg_id,
                        permissions=_full_member_permissions(),
                        use_independent_chat_permissions=True,
                    )
                state = await bot_set_onboarding_restriction_state(tg_id, False, False)
                if state.error:
                    logger.error("Failed to clear onboarding restriction state for %s: %s", tg_id, state.error)
                    return 0
                logger.info("Onboarding restriction removed for %s because an application exists", tg_id)
                return 1
        except TelegramForbiddenError:
            logger.error("Onboarding reconciliation lost Telegram access")
            return 0
        except TelegramBadRequest as exc:
            logger.warning("Onboarding reconciliation failed for %s: %s", tg_id, exc)
            return 0
        except Exception as exc:
            logger.warning("Onboarding reconciliation failed for %s: %s", tg_id, exc)
            return 0
        return 0

    results = await asyncio.gather(*(check(row) for row in candidates), return_exceptions=True)
    for value in results:
        if isinstance(value, int):
            changed += value
        elif isinstance(value, Exception):
            logger.warning("Onboarding reconciliation task failed: %s", value)
    return changed


async def reconcile_community_membership(bot: Bot) -> int:
    if not MODERATION_GROUP_ID:
        logger.warning("Community membership reconciliation skipped: MODERATION_GROUP_ID is not configured")
        return 0

    result = await bot_list_community_membership_candidates()
    if result.error or not isinstance(result.data, list):
        logger.error("Community membership candidate query failed: %s", result.error)
        return 0

    candidates = [row for row in result.data if isinstance(row, dict) and row.get("tg_id")]
    semaphore = asyncio.Semaphore(MAX_CONCURRENCY)
    changed = 0

    async def check(row: dict) -> int:
        tg_id = int(row["tg_id"])
        try:
            async with semaphore:
                member = await bot.get_chat_member(MODERATION_GROUP_ID, tg_id)
            actual_member = _is_active_member(member)
        except TelegramBadRequest as exc:
            if not _is_missing_member_error(exc):
                logger.warning("Membership check failed for %s: %s", tg_id, exc)
                return 0
            actual_member = False
        except TelegramForbiddenError as exc:
            logger.error("Membership reconciliation lost Telegram access: %s", exc)
            return 0
        except Exception as exc:
            logger.warning("Membership check failed for %s: %s", tg_id, exc)
            return 0

        stored_member = bool(row.get("community_is_member"))
        if actual_member == stored_member:
            return 0

        update = await bot_set_community_membership(
            tg_id,
            row.get("username") or "",
            row.get("first_name") or "",
            row.get("last_name") or "",
            row.get("full_name") or "",
            actual_member,
        )
        if update.error:
            logger.error(
                "Failed to reconcile community membership for %s: %s",
                tg_id,
                update.error,
            )
            return 0

        logger.info(
            "Community membership reconciled for %s: %s -> %s",
            tg_id,
            stored_member,
            actual_member,
        )
        return 1

    results = await asyncio.gather(*(check(row) for row in candidates), return_exceptions=True)
    for value in results:
        if isinstance(value, int):
            changed += value
        elif isinstance(value, Exception):
            logger.warning("Community membership reconciliation task failed: %s", value)

    return changed


async def run_community_membership_worker(bot: Bot, stop_event: asyncio.Event):
    await reconcile_community_membership(bot)
    await reconcile_onboarding_restrictions(bot)
    while not stop_event.is_set():
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=RECONCILE_INTERVAL_SECONDS)
        except asyncio.TimeoutError:
            await reconcile_community_membership(bot)
            await reconcile_onboarding_restrictions(bot)
