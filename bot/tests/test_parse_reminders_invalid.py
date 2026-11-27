import pytest
from bot.services.reminders import parse

def test_parse_invalid_reminder():
    assert parse("30m") is None