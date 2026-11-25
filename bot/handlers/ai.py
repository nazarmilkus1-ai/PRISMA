import asyncio
import logging
import os
import re
import time
from html import escape

from aiogram import F, Router, types
from aiogram.filters import Command, CommandObject, StateFilter
from aiogram.fsm.context import FSMContext
from aiogram.dispatcher.event.bases import SkipHandler
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup

import config
from db.rpc import bot_get_profile, bot_get_user_status
from fsm.states import AskForm
from handlers.guide import build_guide
from db.rpc import bot_check_admin_permission
from services import digest
from services.ai import ambient, evals, mod_actions
from services.ai import memory as ai_memory
from services.ai import navigator, sections
from services.ai.admin_tools import run_copilot
from services.ai.bench import run_bench
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.links import link_buttons
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from services.ai.live import live_card, live_intent
from utils.mdhtml import strip_markdown, to_telegram_html
from utils.permissions import get_application_status, has_any_staff_permission, is_admin_mode, require_admin_mode
from utils.rules import rules_text
from utils.validation import Validation

router = Router(name="ai")
# Free-text questions in private chat; registered last so every dialog with its own state wins.
free_router = Router(name="ai_free")
logger = logging.getLogger(__name__)


async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Ask AI a question and return whether it was successful."""
    from services.ai.client import chat, is_configured, model_for
    
    if not is_configured():
        return False
    
    try:
        model = model_for()
        response = await chat(model, question, private=private)
        return response is not None and response != ""
    except Exception as e:
        logger.warning("AI question failed: %s", e)
        return False

async def _answer(message: types.Message, question: str, private: bool = True) -> None:
    """Answer a user question using AI or fallback code."""
    if await _ask_ai(message, question, private):
        return
    await _answer_by_code(message, question, private)

async def _answer_by_code(message: types.Message, question: str, private: bool) -> bool:
    """Fallback: answer using canned code (when AI is unavailable)."""
    # Simple fallback: respond with the question itself as code context
    # In real implementation this would use predefined responses
    return False


async def _status_for_intent(tg_id: int, kind: str | None) -> str:
    """Fetch a user's status only for deterministic answers that need it."""
    valid, error = Validation.validate_telegram_id(tg_id)
    if not valid:
        logger.warning("Invalid Telegram ID in _status_for_intent: %s", error)
        return ""
    if kind not in {"guide", "apply"}:
        return ""
    return str(await bot_get_user_status(tg_id) or "")