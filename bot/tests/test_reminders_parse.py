from services.reminders import parse
from datetime import datetime

NOW = datetime.now()

def test_parse_unrecognized_input():
    result = parse("неправильный текст", NOW)
    assert result is None
