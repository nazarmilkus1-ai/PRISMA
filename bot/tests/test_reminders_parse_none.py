from datetime import datetime
from bot.services.reminders import parse

def test_parse_unrecognized_input():
    result = parse("18:30 ивент", datetime.now())
    assert result is None
