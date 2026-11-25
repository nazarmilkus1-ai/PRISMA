from aiogram import types
from db.rpc import bot_get_profile, bot_get_user_status
from services.ai import navigator, sections, memory as ai_memory
from services.ai.client import AIError, base_url, chat, fallback_model, is_configured, model_for
from services.ai.member_tools import peek_draft, publish, run_member, take_draft
from utils.validation import Validation