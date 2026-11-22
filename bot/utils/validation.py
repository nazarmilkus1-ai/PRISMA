import logging
import re
import uuid
from typing import Optional

logger = logging.getLogger(__name__)

# Регулярки для Minecraft ников
_JAVA_NICK = re.compile(r"^[A-Za-z0-9_]{3,16}$")
_BEDROCK_NICK = re.compile(r"^[A-Za-z0-9_ ]{3,15}$")


class Validation:
    """Централизованная валидация входных данных для обработчиков бота."""

    @staticmethod
    def validate_uuid(value: str, context: str = "UUID") -> tuple[bool, Optional[str]]:
        """Проверяет, что строка — валидный UUID."""
        if not value or not isinstance(value, str):
            logger.warning("Validation failed: %s is empty or not a string", context)
            return False, f"{context} не может быть пустым."
        try:
            uuid.UUID(value)
            return True, None
        except ValueError:
            logger.warning("Validation failed: invalid %s format: %s", context, value)
            return False, f"Неверный формат {context.lower()}."

    @staticmethod
    def validate_minecraft_nick(nick: str, platform: Optional[str] = None) -> tuple[bool, Optional[str]]:
        """Проверяет Minecraft ник (Java или Bedrock).
        
        platform: "java" / "bedrock" или None — тогда подойдёт любой формат.
        """
        if not nick or not isinstance(nick, str):
            logger.warning("Validation failed: minecraft nick is empty or not a string")
            return False, "Ник не может быть пустым."
        
        nick = nick.strip()
        if not nick:
            logger.warning("Validation failed: minecraft nick is whitespace only")
            return False, "Ник не может быть пустым."
        
        kind = (platform or "").strip().lower()
        java_ok = bool(_JAVA_NICK.fullmatch(nick))
        bedrock_ok = bool(_BEDROCK_NICK.fullmatch(nick))
        
        if kind == "java":
            if java_ok:
                return True, None
            logger.warning("Validation failed: invalid Java nick: %s", nick)
            return False, "Java-ник: 3–16 символов, только латиница, цифры и «_», без пробелов."
        
        if kind == "bedrock":
            if bedrock_ok:
                return True, None
            logger.warning("Validation failed: invalid Bedrock nick: %s", nick)
            return False, "Bedrock Gamertag: 3–15 символов, латиница, цифры и пробелы (можно с «_»)."
        
        if java_ok or bedrock_ok:
            return True, None
        
        if len(nick) < 3:
            logger.warning("Validation failed: nick too short: %s", nick)
            return False, "Ник слишком короткий: минимум 3 символа."
        
        logger.warning("Validation failed: nick doesn't match Java or Bedrock format: %s", nick)
        return False, ("Ник не подходит. Java: 3–16 символов, латиница/цифры/«_». "
                       "Bedrock: Gamertag до 15 символов, пробелы разрешены (например, D1lan ok).")

    @staticmethod
    def validate_telegram_id(tg_id: int, context: str = "Telegram ID") -> tuple[bool, Optional[str]]:
        """Проверяет, что Telegram ID — положительное число."""
        if not isinstance(tg_id, int) or tg_id <= 0:
            logger.warning("Validation failed: invalid %s: %s", context, tg_id)
            return False, f"Неверный {context.lower()}."
        return True, None

    @staticmethod
    def validate_text(value: str, min_length: int = 1, max_length: int = 1000, context: str = "Текст") -> tuple[bool, Optional[str]]:
        """Проверяет текст на длину и тип."""
        if not isinstance(value, str):
            logger.warning("Validation failed: %s is not a string", context)
            return False, f"{context} должен быть текстом."
        value = value.strip()
        if len(value) < min_length:
            logger.warning("Validation failed: %s too short (min %d): %s", context, min_length, value)
            return False, f"{context} слишком короткий: минимум {min_length} символов."
        if len(value) > max_length:
            logger.warning("Validation failed: %s too long (max %d): %s...", context, max_length, value[:50])
            return False, f"{context} слишком длинный: максимум {max_length} символов."
        return True, None

    @staticmethod
    def log_error(context: str, user_id: int, action: str, error: Exception, extra: dict = None):
        """Единый формат логирования ошибок с контекстом."""
        log_data = {
            "user_id": user_id,
            "action": action,
            "error_type": type(error).__name__,
            "error_message": str(error),
        }
        if extra:
            log_data.update(extra)
        logger.error("%s failed: %s", context, log_data, exc_info=True)

    @staticmethod
    def log_warning(context: str, user_id: int, action: str, message: str, extra: dict = None):
        """Единый формат логирования предупреждений с контекстом."""
        log_data = {
            "user_id": user_id,
            "action": action,
            "message": message,
        }
        if extra:
            log_data.update(extra)
        logger.warning("%s: %s", context, log_data)