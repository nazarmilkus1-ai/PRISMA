from __future__ import annotations

import asyncio
import html
import logging
import time
from typing import Any

from aiogram import BaseMiddleware, Bot
from aiogram.types import Message

from db.rpc import (
    bot_bridge_claim_for_telegram,
    bot_bridge_enqueue_from_telegram,
    bot_bridge_finish_message,
    bot_get_community_chat_id,
)
from utils.module_runtime import is_module_effectively_enabled

logger = logging.getLogger(__name__)

# The group bot supports legacy natural-language commands as well as slash
# commands. Do not relay those to Minecraft as if they were ordinary chat.
_GROUP_COMMANDS = frozenset({
    "warn", "варн", "пред", "предупреждение", "mute", "мут", "заткнуть",
    "ban", "бан", "чс", "kick", "кик", "unmute", "размут", "unban",
    "unwarn", "разпред", "варны", "warns", "муты", "mutes",
    "who", "кто", "top", "топ", "ники", "nicks", "nicknames",
    "стата", "stats", "кланы", "clans", "клан", "clan", "мойклан",
    "мой_клан", "браки", "marriages", "брак", "marriage",
    "чат", "chat", "население", "population", "смс_ид", "msg_id", "ид", "id",
    "кто_онлайн", "online", "актив", "active", "бот", "призма", "ping",
    "рандом", "random", "данет", "обнять", "пожать", "датьпять", "поддержать",
    "staff", "персонал", "модер", "модерка", "повысить", "promote",
    "понизить", "demote", "снять", "разжаловать", "onboarding", "мои", "мой",
    "статистика", "неактив", "кто_неактив", "profile", "профиль", "сервер", "server",
    "наказания", "апелляция",
})


def _clean_text(value: str, maximum: int = 500) -> str:
    cleaned = " ".join((value or "").replace("\x00", " ").split()).strip()
    if not cleaned or len(cleaned) > maximum:
        return ""
    return "".join(" " if ord(char) < 32 or ord(char) == 127 else char for char in cleaned)


def _looks_like_group_command(value: str) -> bool:
    text = (value or "").strip()
    if not text or text.startswith(("/", "+", "-")):
        return True
    head = text.split(maxsplit=1)[0].strip().casefold().rstrip(":,!?")
    return head in _GROUP_COMMANDS


class MinecraftChatBridge(BaseMiddleware):
    """Telegram group observer plus the durable Minecraft -> Telegram queue worker."""

    def __init__(self) -> None:
        self.community_chat_id: int | None = None
        self._target_refresh_at = 0.0

    async def __call__(self, handler, event: Any, data: dict[str, Any]) -> Any:
        if isinstance(event, Message):
            try:
                await self._enqueue_telegram_message(event)
            except Exception as exc:
                logger.warning("Telegram-to-Minecraft bridge enqueue failed (%s)", type(exc).__name__)
        return await handler(event, data)

    async def _enqueue_telegram_message(self, message: Message) -> None:
        # The background worker normally refreshes this cache, but the first
        # update can arrive before its first poll. Refresh on demand so startup
        # does not silently drop the first normal community messages.
        if self.community_chat_id is None or time.monotonic() >= self._target_refresh_at:
            await self._refresh_community_chat_id()
        if self.community_chat_id is None or message.chat.id != self.community_chat_id:
            return
        if message.chat.type not in {"group", "supergroup"}:
            return
        sender = message.from_user
        if sender is None or sender.is_bot:
            return

        raw_text = message.text or ""
        if not raw_text or _looks_like_group_command(raw_text):
            return
        body = _clean_text(raw_text)
        sender_name = _clean_text(sender.full_name, 128)
        if not body or not sender_name:
            return
        if not await is_module_effectively_enabled("chat"):
            return
        if not await is_module_effectively_enabled("minecraft"):
            return

        result = await bot_bridge_enqueue_from_telegram(
            message.chat.id,
            message.message_id,
            sender.id,
            sender_name,
            body,
        )
        if result.error:
            logger.warning("Telegram bridge message was not queued (%s)", result.error[:120])

    async def _refresh_community_chat_id(self) -> None:
        now = time.monotonic()
        if now < self._target_refresh_at:
            return
        result = await bot_get_community_chat_id()
        self._target_refresh_at = now + 30.0
        if result.error:
            self.community_chat_id = None
            logger.warning("Minecraft chat bridge has no verified community chat target")
            return
        try:
            chat_id = int(result.data)
        except (TypeError, ValueError):
            self.community_chat_id = None
            logger.warning("Community chat ID RPC returned an invalid value")
            return
        if self.community_chat_id != chat_id:
            logger.info("Minecraft chat bridge target refreshed")
        self.community_chat_id = chat_id

    async def _finish(
        self,
        message_id: str,
        lease_token: str,
        status: str,
        error: str | None = None,
    ) -> None:
        result = await bot_bridge_finish_message(
            message_id,
            lease_token,
            status,
            error,
            retry_after_seconds=20,
        )
        if result.error:
            logger.warning("Minecraft-to-Telegram bridge finalization failed (%s)", result.error[:120])

    async def _deliver_minecraft_batch(self, bot: Bot) -> None:
        if self.community_chat_id is None:
            return
        if not await is_module_effectively_enabled("chat"):
            return
        if not await is_module_effectively_enabled("minecraft"):
            return

        result = await bot_bridge_claim_for_telegram(20)
        if result.error:
            logger.warning("Minecraft chat bridge queue claim failed (%s)", result.error[:120])
            return
        payload = result.data
        rows = payload.get("data", []) if isinstance(payload, dict) else []
        if not isinstance(rows, list):
            logger.warning("Minecraft chat bridge queue returned an unexpected payload")
            return
        try:
            target_chat_id = int(payload.get("chat_id", self.community_chat_id))
        except (TypeError, ValueError):
            logger.warning("Minecraft chat bridge queue did not return a verified community chat ID")
            for row in rows:
                if not isinstance(row, dict):
                    continue
                message_id = str(row.get("id") or "")
                lease_token = str(row.get("lease_token") or "")
                if message_id and lease_token:
                    await self._finish(message_id, lease_token, "RETRY", "INVALID_COMMUNITY_CHAT_ID")
            return
        # The claim RPC returns the current canonical target. This avoids a
        # stale in-memory target being used after community settings change.
        self.community_chat_id = target_chat_id

        for row in rows:
            if not isinstance(row, dict):
                continue
            message_id = str(row.get("id") or "")
            lease_token = str(row.get("lease_token") or "")
            if not message_id or not lease_token:
                logger.warning("Claimed Minecraft chat message has no ID or lease token")
                continue
            nickname = _clean_text(str(row.get("minecraft_nickname") or "Minecraft"), 64)
            world = _clean_text(str(row.get("minecraft_world") or "world"), 80)
            body = _clean_text(str(row.get("message") or ""))
            if not nickname or not body:
                await self._finish(message_id, lease_token, "FAILED", "INVALID_QUEUE_PAYLOAD")
                continue

            text = (
                f"🎮 <b>[Minecraft] {html.escape(nickname)} · {html.escape(world)}</b>\n"
                f"{html.escape(body)}"
            )
            try:
                await bot.send_message(
                    chat_id=target_chat_id,
                    text=text,
                    parse_mode="HTML",
                    disable_web_page_preview=True,
                )
            except Exception as exc:
                # Do not persist exception strings: HTTP exception details may contain sensitive data.
                logger.warning("Minecraft chat bridge send failed (%s)", type(exc).__name__)
                await self._finish(message_id, lease_token, "RETRY", type(exc).__name__)
                continue

            await self._finish(message_id, lease_token, "DELIVERED")

    async def run(self, bot: Bot, stop_event: asyncio.Event) -> None:
        while not stop_event.is_set():
            try:
                await self._refresh_community_chat_id()
                await self._deliver_minecraft_batch(bot)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.warning("Minecraft chat bridge worker iteration failed (%s)", type(exc).__name__)

            try:
                await asyncio.wait_for(stop_event.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                pass
