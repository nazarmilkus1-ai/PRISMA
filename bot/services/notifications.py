import asyncio
import logging
import time

from aiogram import Bot

from db.rpc import (
    bot_claim_notifications,
    bot_finish_notification,
    bot_get_community_chat_id,
    bot_get_notification_preference,
    bot_mark_support_message_delivery,
)
from keyboards.inline import social_request_keyboard
from utils.module_runtime import is_module_effectively_enabled

logger = logging.getLogger(__name__)

KIND_TO_PREF = {
    "NEWS": "news",
    "EVENT": "events",
    "SERVER_STATUS": "server_status",
    "CLAN": "clan_news",
    "CLAN_NEWS": "clan_news",
    "SOCIAL": "social",
    "BATTLE": "battles",
    "MARKET": "market",
    "MODERATION": "moderation",
    "POLL": "polls",
}


async def _claim_batch():
    result = await bot_claim_notifications(20)
    if result.error:
        logger.error("notification claim failed: %s", result.error)
        return []
    if not isinstance(result.data, list):
        logger.error("notification claim returned unexpected data: %r", result.data)
        return []
    return [row for row in result.data if isinstance(row, dict)]


async def _preference(row):
    key = KIND_TO_PREF.get(str(row.get("kind") or "").upper())
    if not key or not row.get("user_id"):
        return True

    result = await bot_get_notification_preference(row["user_id"], key)
    if result.error:
        logger.warning("notification preference lookup failed: %s", result.error)
        return True
    return bool(result.data)


async def _finish(
    row_id: str,
    status: str,
    error: str | None = None,
    retry_after_seconds: int | None = None,
):
    result = await bot_finish_notification(
        row_id,
        status,
        error,
        retry_after_seconds,
    )
    if result.error:
        logger.error("notification %s finalization failed: %s", row_id, result.error)


async def run_notification_once(bot: Bot) -> int:
    if not await is_module_effectively_enabled("notifications"):
        logger.info("Notification worker paused because the notifications module is disabled or unavailable")
        return 0

    rows = await _claim_batch()
    for row in rows:
        try:
            if not await _preference(row):
                await _finish(row["id"], "cancelled")
                continue

            tg_id = row.get("telegram_id")
            if not tg_id:
                await _finish(row["id"], "failed", "NO_TELEGRAM_ID")
                continue

            title = row.get("title")
            text = (
                f"{title}\n\n{row.get('body') or ''}"
                if title
                else (row.get("body") or "")
            )

            reply_markup = None
            payload = row.get("data") if isinstance(row.get("data"), dict) else {}
            is_accepted_application = (
                str(row.get("kind") or "").upper() == "APPLICATION"
                and str(payload.get("application_status") or "").upper() == "ACCEPTED"
            )

            # Send the decision independently of invitation creation. Telegram can
            # reject createChatInviteLink because of permissions or configuration;
            # that must never prevent the user from learning that their application
            # was accepted.
            if is_accepted_application:
                text = (
                    f"{text}\n\n"
                    "Следующим сообщением бот отправит персональную ссылку на сообщество. "
                    "Если ссылка не придёт, обратитесь к администрации PRISMA."
                )

            send_kwargs = {"chat_id": int(tg_id), "text": text}
            if payload.get("parse_mode") == "HTML":
                send_kwargs["parse_mode"] = "HTML"
            action = str(payload.get("action") or "").lower()
            request_id = payload.get("request_id")
            if request_id and action in {"marriage_request", "relationship_request"}:
                kind = "MARRIAGE" if action.startswith("marriage_") else "RELATIONSHIP"
                reply_markup = social_request_keyboard(kind, str(request_id))

            await bot.send_message(
                reply_markup=reply_markup,
                **send_kwargs,
            )

            if is_accepted_application:
                try:
                    chat_result = await bot_get_community_chat_id()
                    if chat_result.error:
                        raise RuntimeError(chat_result.error)

                    application_no = payload.get("application_no")
                    invite = await bot.create_chat_invite_link(
                        chat_id=int(chat_result.data),
                        name=f"PRISMA #{application_no}" if application_no else "PRISMA member",
                        member_limit=1,
                        expire_date=int(time.time()) + 7 * 24 * 60 * 60,
                    )
                    invite_link = getattr(invite, "invite_link", None)
                    if not invite_link:
                        raise RuntimeError("Telegram did not return an invite link")

                    await bot.send_message(
                        chat_id=int(tg_id),
                        text=(
                            "🔗 Ваша персональная ссылка на сообщество PRISMA:\n"
                            f"{invite_link}\n\n"
                            "Ссылка одноразовая и действует 7 дней. Не передавайте её другим."
                        ),
                    )
                except Exception as invite_exc:
                    # The acceptance message has already been delivered. Handle the
                    # invite failure locally so the queue does not resend the
                    # decision message and create duplicate notifications.
                    logger.error(
                        "Application acceptance %s was delivered, but invite creation/delivery failed: %s",
                        row.get("id"),
                        invite_exc,
                    )
                    try:
                        await bot.send_message(
                            chat_id=int(tg_id),
                            text=(
                                "⚠️ Ваша анкета уже принята, но ссылку на сообщество "
                                "не удалось отправить автоматически. Обратитесь к администрации PRISMA."
                            ),
                        )
                    except Exception as notice_exc:
                        logger.error(
                            "Application acceptance %s was delivered, but the invite-failure notice also failed: %s",
                            row.get("id"),
                            notice_exc,
                        )

            await _finish(row["id"], "sent")
            support_message_id = payload.get("support_message_id")
            if support_message_id and str(row.get("kind") or "").upper() == "SUPPORT":
                delivery = await bot_mark_support_message_delivery(
                    str(support_message_id),
                    "sent",
                )
                if delivery.error:
                    logger.warning(
                        "support message %s delivery status update failed: %s",
                        support_message_id,
                        delivery.error,
                    )
        except Exception as exc:
            support_message_id = payload.get("support_message_id") if isinstance(row.get("data"), dict) else None
            if support_message_id and str(row.get("kind") or "").upper() == "SUPPORT":
                delivery = await bot_mark_support_message_delivery(
                    str(support_message_id),
                    "failed",
                    str(exc),
                )
                if delivery.error:
                    logger.warning(
                        "support message %s failure status update failed: %s",
                        support_message_id,
                        delivery.error,
                    )
            attempts = int(row.get("attempts") or 1)
            if attempts < 5:
                await _finish(
                    row["id"],
                    "pending",
                    str(exc),
                    retry_after_seconds=min(300, 2 ** attempts * 10),
                )
            else:
                await _finish(row["id"], "failed", str(exc))
    return len(rows)


async def run_notification_worker(bot: Bot, stop_event: asyncio.Event):
    while not stop_event.is_set():
        await run_notification_once(bot)
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=8)
        except asyncio.TimeoutError:
            pass
