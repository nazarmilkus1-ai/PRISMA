import pytest
from bot.services.reminders import parse

def test_parse_30m_returns_none():
    assert parse("30m") is None
