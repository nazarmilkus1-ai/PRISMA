from aiogram import types, Router
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator, sections, ai_memory


router = Router(name="ai")

_ask_ai = None

free_router = router
