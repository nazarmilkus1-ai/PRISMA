import pytest
from bot.services.reminders import parse

def test_invalid_format_30m():
    assert parse("30m") is None
