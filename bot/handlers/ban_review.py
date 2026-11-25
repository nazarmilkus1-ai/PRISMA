from aiogram import Router, types, F
from utils.validation import Validation
from db.rpc import bot_ban_review_keep, bot_ban_review_list, bot_check_admin_permission, bot_lift_punishment

router = Router(name="ban_review")


CB_PREFIX = "ban_review"
