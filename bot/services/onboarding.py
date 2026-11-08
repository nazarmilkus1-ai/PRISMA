import asyncio
import logging
import os
from datetime import datetime
from html import escape
from zoneinfo import ZoneInfo

from aiogram import Bot

from config import MODERATION_GROUP_ID
from db.rpc import bot_claim_onboarding_digest
from keyboards.inline import onboarding_group_keyboard

logger = logging.getLogger(__name__)

TELEGRAM_MESSAGE_LIMIT = 3900
DIGEST_TZ = ZoneInfo(os.getenv("ONBOARDING_DIGEST_TZ", "Europe/Kyiv"))
DIGEST_HOUR = int(os.getenv("ONBOARDING_DIGEST_HOUR", "12"))
NOT_OPENED = "NOT_OPENED"
OPENED_NO_APPLICATION = "OPENED_NO_APPLICATION"


def _display_name(row: dict) -> str:
    value = (
        row.get("first_name")
        or row.get("full_name")
        or row.get("telegram_username")
        or "участник"
    )
    return " ".join(str(value).split())[:32] or "участник"


def _mention(row: dict) -> str:
    try:
        telegram_id = int(row["telegram_id"])
    except (KeyError, TypeError, ValueError):
        return escape(_display_name(row))
    return f'<a href="tg://user?id={telegram_id}">{escape(_display_name(row))}</a>'


def _stage(row: dict) -> str | None:
    stage = str(row.get("onboarding_stage") or "").upper()
    if stage in {NOT_OPENED, OPENED_NO_APPLICATION}:
        return stage
    return NOT_OPENED if not row.get("bot_started_at") else OPENED_NO_APPLICATION


def _render_page(
    not_opened: list[str],
    opened_no_application: list[str],
    total_not_opened: int,
    total_opened_no_application: int,
    page_label: str | None = None,
) -> str:
    title = "📣 <b>PRISMA — список для приглашения</b>"
    if page_label:
        title += f" · {page_label}"

    sections: list[str] = []
    if not_opened:
        sections.append(
            f"🔴 <b>Не открыли бота — {total_not_opened}</b>\n"
            + "\n".join(f"• {name}" for name in not_opened)
        )
    if opened_no_application:
        sections.append(
            f"🟡 <b>Открыли бота, но не подали заявку — {total_opened_no_application}</b>\n"
            + "\n".join(f"• {name}" for name in opened_no_application)
        )

    return (
        f"{title}\n"
        f"<i>Всего: {total_not_opened + total_opened_no_application}</i>\n\n"
        + "\n\n".join(sections)
        + "\n\nОткройте PRISMA и подайте заявку."
    )


def _format_digest_pages(rows: list[dict]) -> list[str]:
    groups = {NOT_OPENED: [], OPENED_NO_APPLICATION: []}
    for row in rows:
        if not isinstance(row, dict) or not row.get("telegram_id"):
            continue
        stage = _stage(row)
        if stage:
            groups[stage].append(_mention(row))

    red = groups[NOT_OPENED]
    yellow = groups[OPENED_NO_APPLICATION]
    if not red and not yellow:
        return []

    one_page = _render_page(red, yellow, len(red), len(yellow))
    if len(one_page) <= TELEGRAM_MESSAGE_LIMIT:
        return [one_page]

    # Telegram has a 4096-character message limit. Split only if necessary;
    # every page retains the requested red/yellow category layout.
    pages: list[dict[str, list[str]]] = []
    current = {NOT_OPENED: [], OPENED_NO_APPLICATION: []}
    items = (
        [(NOT_OPENED, item) for item in red]
        + [(OPENED_NO_APPLICATION, item) for item in yellow]
    )

    for stage, item in items:
        trial = {
            NOT_OPENED: current[NOT_OPENED] + ([item] if stage == NOT_OPENED else []),
            OPENED_NO_APPLICATION: (
                current[OPENED_NO_APPLICATION]
                + ([item] if stage == OPENED_NO_APPLICATION else [])
            ),
        }
        trial_text = _render_page(
            trial[NOT_OPENED], trial[OPENED_NO_APPLICATION],
            len(red), len(yellow), "часть 999/999",
        )
        has_items = bool(current[NOT_OPENED] or current[OPENED_NO_APPLICATION])
        if len(trial_text) > TELEGRAM_MESSAGE_LIMIT and has_items:
            pages.append(current)
            current = {NOT_OPENED: [], OPENED_NO_APPLICATION: []}
        current[stage].append(item)

    if current[NOT_OPENED] or current[OPENED_NO_APPLICATION]:
        pages.append(current)

    return [
        _render_page(
            page[NOT_OPENED], page[OPENED_NO_APPLICATION],
            len(red), len(yellow), f"часть {index}/{len(pages)}",
        )
        for index, page in enumerate(pages, start=1)
    ]


async def deliver_onboarding_digest(bot: Bot, *, force: bool = False) -> tuple[str, int]:
    """Send an aggregate reminder; force=True bypasses the 24-hour cooldown."""
    if not MODERATION_GROUP_ID:
        logger.warning("Onboarding digest disabled: MODERATION_GROUP_ID is not configured")
        return "disabled", 0

    result = await bot_claim_onboarding_digest(limit=1000 if force else 100, force=force)
    if result.error:
        logger.warning("Onboarding digest claim failed: %s", result.error)
        return "error", 0

    rows = result.data if isinstance(result.data, list) else []
    rows = [row for row in rows if isinstance(row, dict) and row.get("telegram_id")]
    messages = _format_digest_pages(rows)
    if not messages:
        return "empty", 0

    for index, message_text in enumerate(messages, start=1):
        try:
            await bot.send_message(
                MODERATION_GROUP_ID,
                message_text,
                reply_markup=onboarding_group_keyboard(),
                parse_mode="HTML",
                disable_notification=True,
            )
        except Exception:
            logger.exception("Failed to send onboarding digest page %s/%s", index, len(messages))
            return "error", len(rows)

    return "sent", len(rows)


async def run_onboarding_reminder_worker(bot: Bot, stop_event: asyncio.Event):
    """Send ONE combined digest per day (at DIGEST_HOUR local time).

    The per-user 24h cooldown in the database made the old hourly worker post
    a new small message every time any single person became due again. Here the
    whole list goes out together; force=True is safe because this loop is the
    only scheduler and it runs at most once per local calendar day.
    """
    if not MODERATION_GROUP_ID:
        logger.warning("Onboarding worker disabled: MODERATION_GROUP_ID is not configured")
        return

    last_sent_on = None
    while not stop_event.is_set():
        now = datetime.now(DIGEST_TZ)
        if now.hour >= DIGEST_HOUR and last_sent_on != now.date():
            try:
                status, _ = await deliver_onboarding_digest(bot, force=True)
                if status in {"sent", "empty"}:
                    last_sent_on = now.date()
            except Exception:
                logger.exception("Unexpected onboarding reminder worker error")

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=600)
        except asyncio.TimeoutError:
            pass
