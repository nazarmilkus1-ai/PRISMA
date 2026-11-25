from utils.validation import Validation

logger = logging.getLogger(__name__)

async def _telegram_member(bot: Bot, tg_id: int):
    ok, error = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in _telegram_member: %s", tg_id)
        return None
    # rest of function
