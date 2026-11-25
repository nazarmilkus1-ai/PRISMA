from utils.validation import Validation

logger = logging.getLogger(__name__)

def _allowed(tg_id: int, action: str) -> bool:
    """Check if user is allowed to perform action."""
    ok, error = Validation.validate_telegram_id(tg_id)
    if not ok:
        logger.warning("Invalid Telegram ID in _allowed: %s", tg_id)
        return False
    # Some logic here
    return True
