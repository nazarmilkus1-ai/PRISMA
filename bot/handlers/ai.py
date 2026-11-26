import asyncio
import logging
import os
import re

from aiogram import types
from utils.validation import Validation
from db.rpc import bot_get_user_status
from services.ai import navigator
