import asyncio
import logging
import os
import re
from unittest.mock import MagicMock

from aiogram import types
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator, ambient, member_tools
from services.ai import memory as ai_memory_module

def is_configured() -> bool:
    return True

async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    valid, error = Validation.validate_telegram_id(tg_id, "Telegram ID для статуса")
    if not valid:
        Validation.log_warning("_status_for_intent", tg_id, "_status_for_intent", error)
        return ""
    if kind == "guide":
        return "PENDING"
    return ""

async def run_member(member_id: int, action: str, **kwargs) -> bool:
    valid, error = Validation.validate_telegram_id(member_id, "Telegram ID для run_member")
    if not valid:
        Validation.log_warning("run_member", member_id, "run_member", error)
        return False
    return True

ai_memory = ai_memory_module
free_router = navigator


async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Ask AI a question and return whether it was successful."""
    from services.ai import ambient
    answer = await ambient.decide(-1001, "Test", question)
    return answer.get("action") == "answer"
