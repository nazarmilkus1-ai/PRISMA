from __future__ import annotations

from aiogram import BaseMiddleware
from aiogram.types import Message

from config import MODERATION_GROUP_ID
from db.rpc import bot_record_telegram_activity, bot_set_community_membership


class TelegramActivityMiddleware(BaseMiddleware):
    async def __call__(self, handler, event, data):
        if (
            isinstance(event, Message)
            and MODERATION_GROUP_ID
            and event.chat.id == MODERATION_GROUP_ID
            and event.from_user
            and not event.from_user.is_bot
        ):
            user = event.from_user
            try:
                await bot_set_community_membership(
                    user.id,
                    user.username or "",
                    user.first_name or "",
                    user.last_name or "",
                    user.full_name,
                    True,
                )
                await bot_record_telegram_activity(event.chat.id, user.id)
            except Exception:
                # Activity tracking must never block moderation or commands.
                pass

        return await handler(event, data)
