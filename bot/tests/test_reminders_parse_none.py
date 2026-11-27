from datetime import datetime
from zoneinfo import ZoneInfo
from bot.services.reminders import parse

def test_parse_unrecognized_input_returns_none():
    result = parse("18:30 ивент", datetime.now(ZoneInfo("Europe/Kyiv")))
    assert result is None
