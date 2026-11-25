from aiogram import Router
import asyncio
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator
from services.ai.member_tools import run_member

router = Router(name="ai")

class AI_Memory:
    async def hydrate(self, *args):
        pass
    
    async def persist(self, *args):
        pass

ai_memory = AI_Memory()
