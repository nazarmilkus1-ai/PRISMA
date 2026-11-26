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
    if kind == "guide":
        return "PENDING"
    return ""

async def run_member(member_id: int, action: str, **kwargs) -> bool:
    return True

ai_memory = ai_memory_module
free_router = navigator
