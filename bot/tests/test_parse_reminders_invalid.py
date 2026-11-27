import pytest
from bot.services.reminders import parse
from datetime import datetime

def test_parse_invalid_input():
    result = parse("30m", now=datetime(2023, 1, 1))
    assert result is None
