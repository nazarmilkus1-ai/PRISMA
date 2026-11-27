import pytest
from datetime import datetime, timedelta
from bot.services.reminders import parse

def test_parse_invalid_30m():
    # '30m' is not a valid reminder format, should return None
    result = parse("30m")
    assert result is None
