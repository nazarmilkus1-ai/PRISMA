import pytest
from bot.services.reminders import parse

def test_parse_invalid_30m():
    result = parse("30m")
    assert result is None
