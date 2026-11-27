from bot.services.reminders import parse
from bot.utils.helpers import NOW

def test_invalid_format_30m():
    result = parse("30m позвонить", NOW)
    assert result is None, f"Expected None for invalid format '30m' but got {result}"