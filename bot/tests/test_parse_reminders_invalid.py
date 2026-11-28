import pytest
from bot.services.reminders import parse

def test_parse_30m_invalid():
    assert parse("30m") is None
