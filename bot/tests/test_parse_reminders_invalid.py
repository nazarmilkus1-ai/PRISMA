import pytest
from services.reminders import parse

def test_parse_reminders_invalid():
    assert parse('30m') is None