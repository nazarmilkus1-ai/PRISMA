import pytest
from bot.services.reminders import parse
from datetime import datetime

def test_parse_invalid_reminder_format():
    result = parse('30m', datetime.now())
    assert result is None
