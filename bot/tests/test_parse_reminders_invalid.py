from bot.services.reminders import parse
from bot.utils import NOW

def test_parse_invalid_input():
    result = parse("30m", NOW)
    assert result is None, "Expected None for invalid input '30m'"