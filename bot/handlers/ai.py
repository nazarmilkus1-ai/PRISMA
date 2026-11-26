import asyncio
import logging
import os
import re

from aiogram import types
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator

async def _answer_by_code(message: types.Message, question: str, private: bool):
    tg_id = message.from_user.id
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI")
    if not valid:
        logger.warning("_answer_by_code: invalid tg_id %s", tg_id)
        await message.answer("❌ Неверный Telegram ID.")
        return
    kind = navigator.fast_kind(question)

async def bot_get_user_status_tg(tg_id):
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID")
    if not valid:
        logger.warning("bot_get_user_status: invalid tg_id %s", tg_id)
        return None
    return await bot_get_user_status(tg_id)

async def run_member(tg_id, question, status, history, flag):
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для AI")
    if not valid:
        logger.warning("run_member: invalid tg_id %s", tg_id)
        return None, []
    # implementation would go here
    return "", []

async def _status_for_intent(intent, question):
    # placeholder implementation
    return ""
